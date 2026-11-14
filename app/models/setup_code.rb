# Until the first account exists, whoever reaches the server could create the
# admin account. The setup page asks for this one-time code, which is only in
# the server's log, so only whoever runs the server can finish setup.
module SetupCode
  ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze # no look-alikes (0/O, 1/I/L)

  module_function

  # (Each parallel test process has its own.)
  def file = Rails.env.test? ? Rails.root.join("tmp", "setup_code-#{Process.pid}") : Rails.root.join("storage", "setup_code")

  # The code, made the first time it's needed and kept until setup is done.
  def current
    return file.read.strip if file.exist?
    code = Array.new(8) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join.insert(4, "-")
    file.dirname.mkpath
    File.write(file, code, perm: 0o600)
    code
  end

  def announce
    Rails.logger.warn("Setup code: #{current}  (enter it on the setup page to create the admin account)")
  end

  def matches?(given)
    normalize = ->(s) { s.to_s.upcase.gsub(/[^A-Z0-9]/, "") }
    ActiveSupport::SecurityUtils.secure_compare(normalize.(given), normalize.(current))
  end

  def clear
    file.delete if file.exist?
  end
end
