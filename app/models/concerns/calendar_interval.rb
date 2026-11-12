# A calendar interval entered as a number and a unit (days, months or years)
# and stored in a days column and a months column (years as 12 months); one
# of the two is used.
#
#   calendar_interval :replacement, days: :replacement_days, months: :replacement_months
#
# gives replacement_every / replacement_unit (for the form), and
# replacement_interval_label ("1 year", "6 months", "90 days").
module CalendarInterval
  extend ActiveSupport::Concern

  UNITS = { "days" => "days", "months" => "months", "years" => "years" }.freeze

  # [count, unit] for display, from the stored columns.
  def self.split(days, months)
    months = months.to_i
    days = days.to_i
    if months.positive? then months % 12 == 0 ? [ months / 12, "years" ] : [ months, "months" ]
    elsif days.positive? then [ days, "days" ]
    end
  end

  def self.label(days, months)
    count, unit = split(days, months)
    count && "#{count} #{count == 1 ? unit.singularize : unit}"
  end

  class_methods do
    # blank: what an empty interval is stored as (nil, or 0 for NOT NULL columns).
    def calendar_interval(name, days:, months:, blank: nil)
      every_ivar = :"@#{name}_every"
      unit_ivar = :"@#{name}_unit"

      define_method(:"#{name}_every") do
        instance_variable_defined?(every_ivar) ? instance_variable_get(every_ivar) : CalendarInterval.split(self[days], self[months])&.first
      end
      define_method(:"#{name}_unit") do
        (instance_variable_get(unit_ivar) if instance_variable_defined?(unit_ivar)) ||
          CalendarInterval.split(self[days], self[months])&.last || "months"
      end
      define_method(:"#{name}_every=") { |v| instance_variable_set(every_ivar, v) }
      define_method(:"#{name}_unit=") { |v| instance_variable_set(unit_ivar, v) }
      define_method(:"#{name}_interval_label") { CalendarInterval.label(self[days], self[months]) }
      define_method(:"#{name}_calendar?") { self[months].to_i.positive? || self[days].to_i.positive? }
      # The date one interval after `date`: months to the same day (or the
      # month's last day), days added.
      define_method(:"#{name}_after") do |date|
        if date.nil? then nil
        elsif self[months].to_i.positive? then date >> self[months].to_i
        elsif self[days].to_i.positive? then date + self[days].to_i
        end
      end

      # Store the entered interval; a bad number leaves the columns alone and
      # is reported by the validation below.
      before_validation do
        next unless instance_variable_defined?(every_ivar)
        raw = instance_variable_get(every_ivar).to_s.strip
        count = Integer(raw, 10, exception: false)
        unit = public_send(:"#{name}_unit")
        if raw.empty?
          self[days] = blank
          self[months] = blank
        elsif count&.positive? && UNITS.key?(unit)
          self[days] = unit == "days" ? count : blank
          self[months] = { "months" => count, "years" => count * 12 }.fetch(unit, blank)
        end
      end
      validate do
        next unless instance_variable_defined?(every_ivar)
        raw = instance_variable_get(every_ivar).to_s.strip
        next if raw.empty? || Integer(raw, 10, exception: false)&.positive?
        errors.add(:"#{name}_every", "must be a whole number more than 0")
      end
    end
  end
end
