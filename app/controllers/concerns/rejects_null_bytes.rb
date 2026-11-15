# No form or API client sends a null byte; some libraries (password hashing,
# file paths) raise on one, so such requests are refused up front.
module RejectsNullBytes
  extend ActiveSupport::Concern

  included { prepend_before_action :reject_null_bytes }

  private

  def reject_null_bytes
    head :bad_request if contains_null_byte?(request.params)
  end

  def contains_null_byte?(value)
    case value
    when String then value.include?("\0")
    when Hash then value.any? { |k, v| contains_null_byte?(k) || contains_null_byte?(v) }
    when Array then value.any? { contains_null_byte?(_1) }
    else false
    end
  end
end
