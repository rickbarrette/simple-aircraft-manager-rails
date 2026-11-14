# Refuse to run in production with a guessable secret key (see SecretKeyCheck).
# Skipped for the image build's asset step, which uses a throwaway key.
if Rails.env.production? && ENV["SECRET_KEY_BASE"].present? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  Rails.application.config.after_initialize { SecretKeyCheck.verify! }
end
