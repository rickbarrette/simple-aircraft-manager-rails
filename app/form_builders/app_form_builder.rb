# Wraps fields with a label, hint, and inline errors using the app's Tailwind classes.
#   <%= f.field :tail_number %>
#   <%= f.field :tach_time, as: :number, step: 0.1 %>
#   <%= f.field :status, as: :select, collection: Aircraft::STATUSES.invert %>
#   <%= f.field :public, as: :checkbox, label: "Show on share links" %>
class AppFormBuilder < ActionView::Helpers::FormBuilder
  def field(method, as: :text, label: nil, hint: nil, collection: nil, include_blank: false, wrapper: {}, **opts)
    label_text = label || method.to_s.humanize
    errors = object.respond_to?(:errors) ? object.errors[method] : []

    if as == :checkbox
      return @template.content_tag(:div, class: [ "flex items-start gap-2", wrapper[:class] ]) do
        check_box(method, { class: "mt-0.5 h-4 w-4 rounded border-slate-300 text-sky-700" }.merge(opts)) +
          @template.content_tag(:div) do
            label(method, label_text, class: "text-sm text-slate-700") +
              (hint ? @template.content_tag(:p, hint, class: "hint") : "".html_safe)
          end
      end
    end

    input_opts = { class: "input" }.merge(opts)
    input =
      case as
      when :textarea then text_area(method, { rows: 4 }.merge(input_opts))
      when :number then number_field(method, input_opts)
      when :date then date_field(method, input_opts)
      when :datetime then datetime_field(method, input_opts)
      when :email then email_field(method, input_opts)
      when :password then password_field(method, input_opts)
      when :file then file_field(method, opts.merge(class: "block text-sm text-slate-600 file:mr-3 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-1.5 file:text-sm file:font-medium hover:file:bg-slate-200"))
      when :select then select(method, collection, { include_blank: include_blank }, input_opts)
      else text_field(method, input_opts)
      end

    @template.content_tag(:div, class: wrapper[:class]) do
      label(method, label_text, class: "label") + input +
        (hint ? @template.content_tag(:p, hint, class: "hint") : "".html_safe) +
        errors.map { |e| @template.content_tag(:p, "#{label_text} #{e}", class: "field-error") }.join.html_safe
    end
  end

  # A calendar interval: a number and a days / months / years choice
  # (see CalendarInterval).
  #   <%= f.interval :replacement, label: "Replace every" %>
  def interval(name, label:, hint: nil, wrapper: {})
    every = :"#{name}_every"
    errors = object.errors[every]
    @template.content_tag(:div, class: wrapper[:class]) do
      label(every, label, class: "label") +
        @template.content_tag(:div, class: "flex gap-2") do
          number_field(every, class: "input min-w-0 flex-1", min: 1, step: 1, inputmode: "numeric") +
            select(:"#{name}_unit", CalendarInterval::UNITS.invert, {}, class: "input w-auto", "aria-label": "#{label} unit")
        end +
        (hint ? @template.content_tag(:p, hint, class: "hint") : "".html_safe) +
        errors.map { |e| @template.content_tag(:p, "#{label} #{e}", class: "field-error") }.join.html_safe
    end
  end

  def errors_summary
    return "".html_safe unless object&.errors&.any?
    @template.content_tag(:div, class: "rounded-md bg-red-50 p-3 text-sm text-red-700 ring-1 ring-red-200") do
      @template.content_tag(:ul, class: "list-disc pl-5") do
        object.errors.full_messages.map { |m| @template.content_tag(:li, m) }.join.html_safe
      end
    end
  end

  def submit(value = nil, **opts)
    super(value, { class: "btn-primary" }.merge(opts))
  end
end
