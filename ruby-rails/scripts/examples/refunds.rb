# frozen_string_literal: true

# Executable teaching example, Rails 7.2+; see references/reliability.md.
# Schema belongs to the isolated integration harness, not an application migration.
require 'active_record'
require 'active_job'
require 'net/http'

class Order < ActiveRecord::Base
  class NotCancellable < StandardError; end
  has_many :audit_events

  def cancel!(reason:, actor_id:)
    with_lock do
      raise NotCancellable, status unless %w[pending paid].include?(status)

      if status == 'paid'
        # Snapshot the immutable, single full-refund intent before changing status.
        self.refund_state = 'pending'
        self.refund_key = "order-#{id}-full-refund"
        self.refund_payment_id = payment_id
        self.refund_amount_cents = total_cents
        self.refund_currency = currency
      end
      self.status = 'cancelled'
      save!
      audit_events.create!(actor_id: actor_id, reason: reason)
      order_id = id
      if refund_state == 'pending'
        # Follows the outer transaction; a savepoint release is not a commit.
        self.class.current_transaction.after_commit { RefundDispatch.call(order_id) }
      end
    end
    self # Cancellation accepted, not proof of a completed refund.
  end
end

class AuditEvent < ActiveRecord::Base
  belongs_to :order
end

module RefundDispatch
  def self.call(order_id)
    job = RefundOrderJob.perform_later(order_id)
    return :queued if job

    ActiveJob::Base.logger.warn("refund enqueue rejected: order_id=#{order_id}")
    :deferred
  rescue ActiveJob::EnqueueError => error
    ActiveJob::Base.logger.warn("refund enqueue failed: order_id=#{order_id} error=#{error.class}")
    :deferred
  end

  # Run periodically through the project's scheduler; duplicates are expected.
  # Other adapter-specific errors should be handled explicitly at this boundary.
  def self.recover
    Order.where(refund_state: %w[pending unknown]).find_each do |order|
      call(order.id)
    end
  end
end

module Refunds
  class UnknownOutcome < StandardError; end
  class Declined < StandardError; end

  # gateway: refund(**intent) -> nonempty receipt ID, lookup(key:) -> ID or
  # :not_found (definitive and safe to submit); otherwise raise UnknownOutcome.
  # The gateway MUST atomically deduplicate concurrent requests with the same
  # key AND reject reuse with a different payment/amount/currency.
  def self.call(order_id, gateway:)
    raise ArgumentError, 'run refunds outside a caller transaction' if Order.current_transaction.open?

    order = Order.find(order_id)
    return :not_required if order.refund_state == 'none'
    return :done if order.refund_state == 'done'
    return :failed if order.refund_state == 'failed'

    intent = {
      key: order.refund_key, payment_id: order.refund_payment_id,
      amount_cents: order.refund_amount_cents, currency: order.refund_currency
    }
    receipt = order.refund_state == 'unknown' ? gateway.lookup(key: intent.fetch(:key)) : :not_found
    receipt = gateway.refund(**intent) if receipt == :not_found
    raise UnknownOutcome, 'unconfirmed receipt' unless receipt.is_a?(String) && !receipt.empty?

    order.with_lock do
      # A concurrent worker may already have confirmed this same intent.
      return :done if order.refund_state == 'done'
      raise UnknownOutcome, 'intent no longer recoverable' unless %w[pending unknown].include?(order.refund_state)
      order.update!(refund_state: 'done', refund_id: receipt)
    end
    :done
  rescue Net::OpenTimeout, Net::ReadTimeout, UnknownOutcome
    # Do not let a late timeout overwrite another worker's confirmed result.
    Order.where(id: order_id, refund_state: 'pending').update_all(refund_state: 'unknown')
    raise
  rescue Declined
    Order.where(id: order_id, refund_state: %w[pending unknown]).update_all(refund_state: 'failed')
    :failed
  end
end

class RefundOrderJob < ActiveJob::Base
  retry_on Net::OpenTimeout, Net::ReadTimeout, Refunds::UnknownOutcome,
           wait: :polynomially_longer, attempts: 5

  def perform(order_id)
    Refunds.call(order_id, gateway: PaymentGateway) # Application-owned protocol adapter.
  end
end
