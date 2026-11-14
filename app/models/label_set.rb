# Display labels for stored values, from the locale file and in the current
# locale: LabelSet.new("aircraft.statuses", %w[AVAILABLE MX]) reads
# labels.aircraft.statuses.AVAILABLE. It answers like the hash it replaces
# ({ "AVAILABLE" => "Available", ... }): [], fetch, keys, key?, invert, each…
class LabelSet
  include Enumerable

  attr_reader :keys

  def initialize(scope, keys)
    @scope = "labels.#{scope}"
    @keys = keys.freeze
    freeze
  end

  def [](key) = (I18n.t(key.to_s, scope: @scope) if key?(key))
  def fetch(key, *default) = key?(key) ? self[key] : (default.any? ? default.first : yield(key))
  def key?(key) = @keys.include?(key)
  def to_h = @keys.index_with { self[_1] }
  def each(&) = to_h.each(&)
  def each_key(&) = @keys.each(&)
  def values = to_h.values
  def invert = to_h.invert
  def key(label) = to_h.key(label)
  def except(*drop) = to_h.except(*drop)
  def slice(*keep) = to_h.slice(*keep)
  def size = @keys.size

  alias include? key?
end
