# frozen_string_literal: true

# In-memory SQLite verifies callback sequencing, NOT PostgreSQL row locks.
gem "minitest", "~> 5.0"
require "minitest/autorun"
require "active_record"
require "active_job"
require "logger"
require_relative "enqueue"

puts "ActiveRecord #{ActiveRecord::VERSION::STRING}; ActiveJob #{ActiveJob::VERSION::STRING}; SQLite callback checks only"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:intents) { |table| table.string :name }
end
ActiveJob::Base.logger = Logger.new(File::NULL)

class Intent < ActiveRecord::Base; end

class ExampleJob < ActiveJob::Base
  self.enqueue_after_transaction_commit = false
  self.queue_adapter = :test
  def perform(id); end
end

class AbortedJob < ExampleJob
  before_enqueue { throw :abort }
end

class RejectingAdapter
  def enqueue(_job)
    raise ActiveJob::EnqueueError, "queue unavailable"
  end
  def enqueue_at(job, _time)
    enqueue(job)
  end
end

class TransactionsTest < Minitest::Test
  def setup
    Intent.delete_all
    ExampleJob.queue_adapter = :test
    ExampleJob.queue_adapter.enqueued_jobs.clear
  end

  def test_active_job_can_return_false_without_raising
    ExampleJob.queue_adapter = RejectingAdapter.new
    job = ExampleJob.new(1)
    assert_equal false, job.enqueue
    assert_instance_of ActiveJob::EnqueueError, job.enqueue_error
    error = assert_raises(ActiveJob::EnqueueError) do
      EnqueueExample.enqueue_now!(ExampleJob.new(1))
    end
    assert_equal "queue unavailable", error.message
  end

  def test_callback_abort_is_also_a_rejection
    job = AbortedJob.new(1)
    assert_equal false, job.enqueue
    assert_nil job.enqueue_error
    assert_raises(ActiveJob::EnqueueError) { EnqueueExample.enqueue_now!(AbortedJob.new(1)) }
  end

  def test_inner_transaction_return_is_not_outer_commit
    Intent.transaction do
      intent = Intent.transaction { Intent.create!(name: "pending") }
      ExampleJob.perform_later(intent.id)
      assert_equal 1, ExampleJob.queue_adapter.enqueued_jobs.size
      raise ActiveRecord::Rollback
    end
    assert_equal 0, Intent.count
    assert_equal 1, ExampleJob.queue_adapter.enqueued_jobs.size
  end

  def test_after_all_transactions_commit_waits_for_outer_commit
    Intent.transaction do
      Intent.transaction(requires_new: true) do
        id = Intent.create!(name: "pending").id
        ActiveRecord.after_all_transactions_commit do
          EnqueueExample.enqueue_now!(ExampleJob.new(id))
        end
      end
      assert_empty ExampleJob.queue_adapter.enqueued_jobs
    end
    assert_equal 1, ExampleJob.queue_adapter.enqueued_jobs.size
    assert_equal 1, Intent.count
  end

  def test_outer_rollback_discards_enqueue_callback
    Intent.transaction do
      Intent.transaction(requires_new: true) do
        id = Intent.create!(name: "pending").id
        ActiveRecord.after_all_transactions_commit { ExampleJob.perform_later(id) }
      end
      raise ActiveRecord::Rollback
    end
    assert_empty ExampleJob.queue_adapter.enqueued_jobs
    assert_equal 0, Intent.count
  end

  def test_enqueue_failure_after_commit_does_not_rollback_intent
    ExampleJob.queue_adapter = RejectingAdapter.new
    assert_raises(ActiveJob::EnqueueError) do
      Intent.transaction do
        id = Intent.create!(name: "pending").id
        ActiveRecord.after_all_transactions_commit do
          EnqueueExample.enqueue_now!(ExampleJob.new(id))
        end
      end
    end
    assert_equal ["pending"], Intent.pluck(:name)
  end
end
