# frozen_string_literal: true

gem "minitest", "~> 5.0"
require "minitest/autorun"

class RubySemanticsTest < Minitest::Test
  def test_filter_map_drops_false_while_compact_preserves_it
    values = [false, nil, 0, ""]
    assert_equal [false, 0, ""], values.map { |item| item }.compact
    assert_equal [0, ""], values.filter_map { |item| item }
  end

  def test_safe_navigation_does_not_short_circuit_false
    receiver = false
    assert_equal false, receiver && receiver.upcase
    assert_raises(NoMethodError) { receiver&.upcase }
  end

  def test_false_memoization_needs_presence_not_truthiness
    calls = 0
    cache = {}
    2.times { cache[:result] ||= (calls += 1; false) }
    assert_equal 2, calls
    calls = 0
    cache = {}
    2.times { cache[:result] = (calls += 1; false) unless cache.key?(:result) }
    assert_equal 1, calls
    assert_equal false, cache.fetch(:result)
  end

  def test_data_is_not_deeply_immutable
    value_class = Data.define(:items)
    items = ["first"]
    value = value_class.new(items: items)
    assert value.frozen?
    items << "second"
    assert_equal ["first", "second"], value.items
    assert_raises(FrozenError) { value.instance_variable_set(:@other, true) }
  end
end
