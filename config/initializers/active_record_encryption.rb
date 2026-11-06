# Keys for Active Record encryption (used for stored API keys), derived from
# SECRET_KEY_BASE so no extra secrets are needed. Changing SECRET_KEY_BASE
# makes previously stored API keys unreadable; they'd need re-entering.
Rails.application.config.after_initialize do
  generator = Rails.application.key_generator
  ActiveRecord::Encryption.configure(
    primary_key: generator.generate_key("active_record_encryption/primary_key", 32).unpack1("H*"),
    deterministic_key: generator.generate_key("active_record_encryption/deterministic_key", 32).unpack1("H*"),
    key_derivation_salt: generator.generate_key("active_record_encryption/key_derivation_salt", 32).unpack1("H*")
  )
end
