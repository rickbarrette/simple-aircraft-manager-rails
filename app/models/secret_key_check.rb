# The application secret key signs the sign-in cookie and protects stored
# secrets (two-factor keys, API keys), so anyone who can guess it can sign in
# as anyone. A placeholder or short key stops the app from starting; one
# shorter than what `bin/rails secret` makes is reported by sam:doctor.
module SecretKeyCheck
  MIN = 32         # below this, refuse to start
  RECOMMENDED = 64 # below this, warn
  PLACEHOLDERS = %w[change-me changeme change_me secret password your-secret-key replace-me example].freeze

  module_function

  # :ok, :weak or :unsafe
  def strength(key = ENV["SECRET_KEY_BASE"].to_s)
    return :unsafe if PLACEHOLDERS.include?(key.strip.downcase) || key.length < MIN || key.chars.uniq.size < 10
    key.length < RECOMMENDED ? :weak : :ok
  end

  def verify!(key = ENV["SECRET_KEY_BASE"].to_s)
    case strength(key)
    when :unsafe
      abort "SECRET_KEY_BASE is a placeholder or too short (#{key.length} characters). " \
            "Set it to the output of `bin/rails secret` (128 random characters) and start again."
    when :weak
      Rails.logger.warn("[security] SECRET_KEY_BASE is only #{key.length} characters; `bin/rails secret` makes 128.")
    end
  end
end
