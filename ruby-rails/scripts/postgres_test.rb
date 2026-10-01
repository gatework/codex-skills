# frozen_string_literal: true

require 'minitest/autorun'
require 'logger'
require 'stringio'
require_relative 'examples/refunds'
require_relative 'example_loader'

root = ENV.fetch('RR_PG_ROOT') { abort 'Run scripts/run_postgres.rb to create an isolated database.' }
abort 'Not a temporary test cluster' unless File.basename(root).start_with?('rr-pg-') && File.file?(File.join(root, 'data/PG_VERSION'))
ActiveRecord::Base.establish_connection(
  adapter: 'postgresql', host: root, port: 5432, database: 'ruby_rails_skill_test',
  pool: 6, checkout_timeout: 5, variables: {statement_timeout: '5000', lock_timeout: '3000'}
)
connection = ActiveRecord::Base.connection
actual = connection.select_value('SHOW data_directory')
abort 'Refusing to use a different cluster' unless File.realpath(actual) == File.realpath(File.join(root, 'data'))
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :orders do |t|
    t.string :status, null: false
    t.string :payment_id
    t.bigint :total_cents, null: false
    t.string :currency, null: false
    t.string :refund_state, null: false, default: 'none'
    t.string :refund_key
    t.string :refund_payment_id
    t.bigint :refund_amount_cents
    t.string :refund_currency
    t.string :refund_id
  end
  add_index :orders, :refund_key, unique: true
  add_check_constraint :orders, "total_cents >= 0", name: 'nonnegative_total'
  add_check_constraint :orders, "status IN ('pending','paid','shipped','cancelled')", name: 'order_status'
  add_check_constraint :orders, "status != 'paid' OR payment_id IS NOT NULL", name: 'paid_payment'
  add_check_constraint :orders, "status != 'paid' OR total_cents > 0", name: 'positive_payment'
  add_check_constraint :orders, "refund_state IN ('none','pending','unknown','done','failed')", name: 'refund_state'
  add_check_constraint :orders, <<~SQL, name: 'refund_intent'
    refund_state = 'none' OR (
      status = 'cancelled' AND refund_key IS NOT NULL AND refund_payment_id IS NOT NULL
      AND refund_amount_cents IS NOT NULL AND refund_amount_cents > 0 AND refund_currency IS NOT NULL
    )
  SQL
  add_check_constraint :orders, "refund_state != 'done' OR refund_id IS NOT NULL", name: 'refund_receipt'
  create_table :audit_events do |t|
    t.references :order, null: false, foreign_key: true
    t.bigint :actor_id, null: false
    t.string :reason
  end
  create_table :sync_runs do |t|
    t.string :state, null: false
    t.string :claim_token
    t.datetime :claimed_at
    t.jsonb :result
  end
end
ExampleLoader.load_example('references/reliability.md', 'sync_run')

# This verifies our use of a stated gateway protocol, not a real provider.
class GatewayFake
  attr_reader :effects, :requests, :lookups
  attr_accessor :timeout_once, :decline, :lookup_unknown

  def initialize
    @mutex = Mutex.new
    @records = {}
    @effects = @requests = @lookups = 0
  end

  def refund(key:, **payload)
    @mutex.synchronize do
      @requests += 1
      raise Refunds::Declined if decline
      existing = @records[key]
      raise ArgumentError, 'idempotency payload conflict' if existing && existing.first != payload
      unless existing
        @effects += 1
        @records[key] = [payload, "receipt-#{@effects}"]
      end
      if timeout_once
        self.timeout_once = false
        raise Net::ReadTimeout
      end
      @records.fetch(key).last
    end
  end

  def lookup(key:)
    @mutex.synchronize do
      @lookups += 1
      raise Refunds::UnknownOutcome if lookup_unknown
      @records.key?(key) ? @records.fetch(key).last : :not_found
    end
  end
end

class RefundsTest < Minitest::Test
  def setup
    AuditEvent.delete_all
    Order.delete_all
    SyncRun.delete_all
    ActiveJob::Base.logger = Logger.new(StringIO.new)
    RefundOrderJob.queue_adapter = :test
    @gateway = GatewayFake.new
  end

  def order(status: 'paid')
    Order.create!(status: status, total_cents: 1200, currency: 'USD', payment_id: status == 'paid' ? 'payment-1' : nil)
  end

  def cancel(record)
    record.cancel!(reason: 'changed mind', actor_id: 42)
  end

  def jobs
    RefundOrderJob.queue_adapter.enqueued_jobs
  end

  # Independent connections and a barrier; every wait has a bounded deadline.
  def race(count = 2, &block)
    ready = Queue.new
    start = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          raise 'start barrier timed out' unless start.pop(timeout: 5)
          block.call(index)
        end
      end.tap { |thread| thread.report_on_exception = false }
    end
    count.times { raise 'ready barrier timed out' unless ready.pop(timeout: 5) }
    count.times { start << true }
    threads.map do |thread|
      raise 'worker timed out' unless thread.join(8)
      thread.value
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end

  def test_outer_commit_defers_dispatch_and_preserves_audit
    record = order
    Order.transaction do
      assert_same record, cancel(record)
      assert_empty jobs
      assert_equal 'pending', record.refund_state
    end
    assert_equal 1, jobs.size
    assert_equal [record.id], jobs.first.fetch(:args)
    assert_equal 1, record.audit_events.count
    assert_equal [1200, 'USD', 'payment-1'], [record.refund_amount_cents, record.refund_currency, record.refund_payment_id]
  end

  def test_outer_rollback_leaves_no_intent_audit_or_dispatch
    record = order
    Order.transaction do
      cancel(record)
      raise ActiveRecord::Rollback
    end
    assert_equal 'paid', record.reload.status
    assert_equal 'none', record.refund_state
    assert_empty jobs
    assert_equal 0, record.audit_events.count
  end

  def test_savepoint_callback_is_dropped_on_rollback
    record = order
    Order.transaction do
      Order.transaction(requires_new: true) do
        cancel(record)
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 'paid', record.reload.status
    assert_empty jobs
  end

  def test_unpaid_cancel_never_refunds
    record = cancel(order(status: 'pending'))
    assert_empty jobs
    assert_equal :not_required, Refunds.call(record.id, gateway: @gateway)
    assert_equal 0, @gateway.requests
  end

  def test_invalid_transition_preserves_existing_audit
    record = cancel(order)
    jobs.clear
    assert_raises(Order::NotCancellable) { cancel(record) }
    assert_equal 1, record.audit_events.count
    assert_empty jobs
  end

  def test_concurrent_cancel_writes_one_audit_and_one_intent
    record = order
    results = race do
      cancel(Order.find(record.id))
      :accepted
    rescue Order::NotCancellable
      :rejected
    end
    assert_equal [:accepted, :rejected], results.sort
    assert_equal 1, record.audit_events.count
    assert_equal 'pending', record.reload.refund_state
    assert_equal 1, jobs.size
  end

  def test_enqueue_false_retains_intent_and_scanner_recovers
    adapter = Object.new
    def adapter.enqueue(job); raise ActiveJob::EnqueueError, 'offline'; end
    def adapter.enqueue_at(job, _timestamp); enqueue(job); end
    RefundOrderJob.queue_adapter = adapter
    record = cancel(order)
    assert_equal 'cancelled', record.reload.status
    assert_equal 'pending', record.refund_state
    assert_equal :deferred, RefundDispatch.call(record.id)
    RefundOrderJob.queue_adapter = :test
    RefundDispatch.recover
    assert_equal [record.id], jobs.first.fetch(:args)
  end

  def test_adapter_exception_does_not_rollback_committed_cancellation
    adapter = Object.new
    def adapter.enqueue(_job); raise IOError, 'adapter transport failed'; end
    def adapter.enqueue_at(job, _timestamp); enqueue(job); end
    RefundOrderJob.queue_adapter = adapter
    record = order
    assert_raises(IOError) { cancel(record) }
    assert_equal 'cancelled', record.reload.status
    assert_equal 'pending', record.refund_state
    assert_equal 1, record.audit_events.count
  end

  def test_repeat_execution_has_one_remote_effect
    record = cancel(order)
    assert_equal :done, Refunds.call(record.id, gateway: @gateway)
    assert_equal :done, Refunds.call(record.id, gateway: @gateway)
    assert_equal 1, @gateway.effects
    assert_equal 1, @gateway.requests
  end

  def test_job_executes_the_domain_operation
    record = cancel(order)
    Object.const_set(:PaymentGateway, @gateway)
    assert_equal :done, RefundOrderJob.perform_now(record.id)
    assert_equal 'done', record.reload.refund_state
    assert_equal 1, @gateway.effects
  ensure
    Object.send(:remove_const, :PaymentGateway) if Object.const_defined?(:PaymentGateway, false)
  end

  def test_refund_rejects_an_outer_transaction_before_remote_io
    record = cancel(order)
    Order.transaction do
      assert_raises(ArgumentError) { Refunds.call(record.id, gateway: @gateway) }
    end
    assert_equal 0, @gateway.requests
    assert_equal 'pending', record.reload.refund_state
  end

  def test_concurrent_refunds_have_one_remote_effect
    record = cancel(order)
    assert_equal [:done, :done], race { Refunds.call(record.id, gateway: @gateway) }
    assert_equal 1, @gateway.effects
    assert_equal 'done', record.reload.refund_state
  end

  def test_effect_then_timeout_recovers_by_lookup
    record = cancel(order)
    @gateway.timeout_once = true
    assert_raises(Net::ReadTimeout) { Refunds.call(record.id, gateway: @gateway) }
    assert_equal 'unknown', record.reload.refund_state
    assert_equal :done, Refunds.call(record.id, gateway: @gateway)
    assert_equal 1, @gateway.requests
    assert_equal 1, @gateway.lookups
    assert_equal 1, @gateway.effects
  end

  def test_unconfirmed_lookup_does_not_resubmit
    record = cancel(order)
    record.update!(refund_state: 'unknown')
    @gateway.lookup_unknown = true
    assert_raises(Refunds::UnknownOutcome) { Refunds.call(record.id, gateway: @gateway) }
    assert_equal 'unknown', record.reload.refund_state
    assert_equal 0, @gateway.requests
  end

  def test_definitive_not_found_allows_same_key_submission
    record = cancel(order)
    record.update!(refund_state: 'unknown')
    assert_equal :done, Refunds.call(record.id, gateway: @gateway)
    assert_equal 1, @gateway.lookups
    assert_equal 1, @gateway.effects
  end

  def test_confirmed_decline_is_terminal
    record = cancel(order)
    @gateway.decline = true
    assert_equal :failed, Refunds.call(record.id, gateway: @gateway)
    assert_equal :failed, Refunds.call(record.id, gateway: @gateway)
    assert_equal 'failed', record.reload.refund_state
    assert_equal 1, @gateway.requests
    jobs.clear
    RefundDispatch.recover
    assert_empty jobs
  end

  def test_same_key_different_payload_is_rejected_by_gateway_contract
    payload = {key: 'k', payment_id: 'p', amount_cents: 12, currency: 'USD'}
    @gateway.refund(**payload)
    assert_raises(ArgumentError) { @gateway.refund(**payload.merge(amount_cents: 13)) }
    assert_equal 1, @gateway.effects
  end

  def test_late_timeout_does_not_overwrite_confirmed_result
    record = cancel(order)
    reached = Queue.new
    release = Queue.new
    delayed = Object.new
    delayed.define_singleton_method(:refund) do |**_intent|
      reached << true
      raise 'release timed out' unless release.pop(timeout: 5)
      raise Net::ReadTimeout
    end
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Refunds.call(record.id, gateway: delayed)
      rescue Net::ReadTimeout
        :timed_out
      end
    end
    thread.report_on_exception = false
    assert reached.pop(timeout: 5), 'gateway was not reached'
    assert_equal :done, Refunds.call(record.id, gateway: @gateway)
    release << true
    assert thread.join(8), 'late worker timed out'
    assert_equal :timed_out, thread.value
    assert_equal 'done', record.reload.refund_state
  ensure
    thread&.kill if thread&.alive?
    thread&.join
  end

  def test_unique_refund_key_is_a_database_constraint
    first = cancel(order)
    second = order(status: 'pending')
    assert_raises(ActiveRecord::RecordNotUnique) { second.update!(refund_key: first.refund_key) }
  end

  def test_unique_refund_key_under_concurrent_inserts
    results = race do
      Order.create!(status: 'pending', total_cents: 12, currency: 'USD', refund_key: 'same-key')
      :created
    rescue ActiveRecord::RecordNotUnique
      :conflict
    end
    assert_equal [:conflict, :created], results.sort
    assert_equal 1, Order.where(refund_key: 'same-key').count
  end

  def test_database_rejects_invalid_amount_even_when_validations_are_bypassed
    record = order
    assert_raises(ActiveRecord::StatementInvalid) { record.update_columns(total_cents: -1) }
    assert_equal 1200, record.reload.total_cents
  end

  def test_unique_conflict_savepoint_preserves_outer_transaction
    first = cancel(order)
    second = order(status: 'pending')
    Order.transaction do
      assert_raises(ActiveRecord::RecordNotUnique) do
        Order.transaction(requires_new: true) { second.update!(refund_key: first.refund_key) }
      end
      second.reload.update!(total_cents: 1400)
    end
    assert_equal 1400, second.reload.total_cents
  end

  def test_claim_has_one_owner_and_stale_owner_cannot_finish
    record = SyncRun.create!(state: 'pending')
    tokens = race { |index| SyncRun.claim(record.id, token: "worker-#{index}") }.compact
    assert_equal 1, tokens.size
    record.update!(claim_token: 'replacement', state: 'running')
    assert_raises(SyncRun::ClaimLost) { record.finish!(tokens.first, {'value' => 'old'}) }
    record.finish!('replacement', {'value' => 'new'})
    assert_equal({'value' => 'new'}, record.reload.result)
  end
end

puts "Runtime: Ruby #{RUBY_VERSION}; ActiveRecord #{ActiveRecord::VERSION::STRING}; ActiveJob #{ActiveJob::VERSION::STRING}; PostgreSQL #{connection.select_value('SHOW server_version')}"
Minitest.after_run { ActiveRecord::Base.connection_pool.disconnect! }
