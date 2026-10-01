# frozen_string_literal: true

require 'minitest/autorun'
require 'set'
require 'active_model'
require_relative 'example_loader'
ExampleLoader.load_example('references/ruby.md', 'money')
ExampleLoader.load_example('references/metaprogramming.md', 'forwarding')
ExampleLoader.load_example('references/workflows.md', 'settings')
ExampleLoader.load_example('references/rails.md', 'transfer_form')

class ContractsTest < Minitest::Test
  def test_settings_preserve_false_and_default_only_missing_or_nil
    assert_equal true, Settings.new({}).notifications_enabled
    assert_equal true, Settings.new(notifications: nil).notifications_enabled
    assert_equal false, Settings.new(notifications: false).notifications_enabled
    assert_equal true, Settings.new(notifications: true).notifications_enabled
  end

  def test_collection_return_contracts
    array = [1, 2]
    assert_same array, array.sort!
    assert_nil array.compact!
    assert_nil array.uniq!
    assert_nil array.find { false }
    assert_equal [false], [false, nil].compact
    assert_empty [false, nil].filter_map { |value| value }
  end

  def test_keyword_and_block_forwarding
    [ForwardChild.new, ForwardProxy.new(ForwardTarget.new)].each do |target|
      assert_equal [2, false, 6], target.call(2, enabled: false) { |n| n * 3 }
      assert_raises(ArgumentError) { target.call(2, {enabled: false}) { |n| n } }
    end
  end

  def test_super_parentheses_preserve_implicit_block
    parent = Class.new { def call; yield; end }
    child = Class.new(parent) { def call; super(); end }
    assert_equal :preserved, child.new.call { :preserved }
  end

  def test_money_owns_currency_and_has_stable_hash_membership
    currency = +'USD'
    money = Money.new(cents: 100, currency: currency)
    index = {money => :found}
    currency.replace('EUR')
    assert_equal 'USD', money.currency
    assert money.currency.frozen?
    assert_equal :found, index[Money.new(cents: 100, currency: 'USD')]
    assert_equal 1, Set[money, Money.new(cents: 100, currency: 'USD')].size
    assert_equal Money.new(cents: 125, currency: 'USD'), money + Money.new(cents: 25, currency: 'USD')
    refute_equal money, Money.new(cents: 100, currency: 'EUR')
    assert_raises(ArgumentError) { money < Money.new(cents: 100, currency: 'EUR') }
    assert_raises(ArgumentError) { Money.new(cents: 1.5, currency: 'USD') }
    assert_raises(ArgumentError) { Money.new(cents: 1, currency: :USD) }
    assert_raises(ArgumentError) { money + 1 }
  end

  def test_form_accepts_only_explicit_integer_protocol
    [12, '12', '0012'].each do |raw|
      form = TransferForm.new(from_account_id: '1', to_account_id: 2, amount_cents: raw)
      assert form.valid?, form.errors.full_messages.inspect
      assert_equal({from_account_id: 1, to_account_id: 2, amount_cents: 12}, form.parsed_attributes)
    end
  end

  def test_form_rejects_bad_types_without_publishing_partial_attributes
    [nil, false, true, '', '12oops', '1.5', 1.5, [], {}, ' 12', '+12', '-1', 0, 2**63, '9' * 20].each do |raw|
      form = TransferForm.new(from_account_id: '1', to_account_id: 2, amount_cents: raw)
      refute form.valid?, "unexpected valid input: #{raw.inspect}"
      assert_includes form.errors.attribute_names, :amount_cents
      assert_nil form.parsed_attributes
    end
  end

  def test_form_revalidation_clears_old_result_and_detects_same_account
    form = TransferForm.new(from_account_id: '1', to_account_id: '2', amount_cents: 12)
    assert form.valid?
    form.amount_cents = '12oops'
    refute form.valid?
    assert_nil form.parsed_attributes
    form.amount_cents = 12
    form.to_account_id = '01'
    refute form.valid?
    assert_includes form.errors.attribute_names, :to_account_id
  end
end

puts "Runtime: Ruby #{RUBY_VERSION}; ActiveModel #{ActiveModel::VERSION::STRING}"
