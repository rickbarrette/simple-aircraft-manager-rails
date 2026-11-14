# Suggested text for the procedures fields the owner fills in: generated
# from the installation's configuration where the app knows the facts, with
# [bracketed] blanks for what only the owner knows. Inserted into the form
# for review; a revision can't be adopted while any blank is left.
module ProceduresTemplates
  module_function

  def hosting
    [
      t(:server, location: t(docker? ? :server_docker : :server_plain)),
      t(:network, https: https_sentence),
      t(:sign_in, sentence: sign_in_sentence, min: User::PASSWORD_MIN, minutes: User::LOCK_FOR.in_minutes.to_i,
                  tries: User::LOCK_AFTER, days: Authentication::SESSION_IDLE_TIMEOUT.in_days.to_i),
      t(Sso.enabled? ? :signing_sso : :signing),
      t(:updates),
      t(:secret_key)
    ].join("\n\n")
  end

  def additional
    since = Aircraft.where.not(electronic_records_since: nil).minimum(:electronic_records_since)
    [
      t(:who_makes_entries), t(:outside_signers), t(:account_problems), t(:share_links), t(:retention),
      t(:paper_records, since: since ? I18n.l(since, format: :long) : t(:since_blank)),
      t(:shop_visits), t(:sale)
    ].join("\n\n")
  end

  def https? = Rails.application.config.force_ssl

  def https_sentence = t(https? ? :https_on : :https_off)

  def sign_in_sentence
    if Sso.enabled? && !Sso.password_login? then t(:sign_in_sso_only, provider: Sso.label)
    elsif Sso.enabled? then t(:sign_in_sso, provider: Sso.label)
    else t(:sign_in_password)
    end
  end

  def docker? = File.exist?("/.dockerenv")

  def t(key, **opts) = I18n.t(key, scope: "services.procedures_templates", **opts)
end
