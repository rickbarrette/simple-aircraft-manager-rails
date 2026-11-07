# Suggested text for the procedures fields the owner fills in: generated
# from the installation's configuration where the app knows the facts, with
# [bracketed] blanks for what only the owner knows. Inserted into the form
# for review; a revision can't be adopted while any blank is left.
module ProceduresTemplates
  module_function

  def hosting
    [
      "**Server.** The system runs #{docker? ? 'as a Docker container on a server' : 'on a server'} at [location, e.g. the owner's home or a hosting provider]. " \
      "Its data (the database, the uploaded files and the nightly verified database copies) is on that server's storage volume. " \
      "Only [the owner] has administrative access to the server.",
      "**Network access.** [How the system is reached: e.g. directly from the internet at its own address, only on the home network, or over a VPN.] #{https_sentence}",
      "**Sign-in.** #{sign_in_sentence} Password accounts require at least #{User::PASSWORD_MIN} characters, reject passwords found in known data breaches, " \
      "lock for #{User::LOCK_FOR.inspect} after #{User::LOCK_AFTER} failed attempts in a row, and can add an authenticator app. " \
      "Sessions end after #{Authentication::SESSION_IDLE_TIMEOUT.inspect} unused.",
      "**Signing.** Signing an entry always requires the signer to re-enter their password (and authenticator code if enabled)#{' or to sign in again with single sign-on' if Sso.enabled?}.",
      "**Updates.** Software updates are installed by [the owner] from [the project's published container images]. Each version is recorded by the system under Software versions.",
      "**Secret key.** The application secret key (SECRET_KEY_BASE), needed to verify electronic signatures and to restore from backup, is kept by the owner off the server in [a password manager]."
    ].join("\n\n")
  end

  def additional
    since = Aircraft.where.not(electronic_records_since: nil).minimum(:electronic_records_since)
    [
      "**Who makes entries.** The owner enters maintenance records. A mechanic who performs work signs their own entry: through a signing invitation, with their own account in the system, " \
      "or by signing a printed entry in ink. The owner signs only preventive maintenance they performed under 14 CFR 43.3(g), with their pilot certificate.",
      "**Outside signers.** Signing invitations are sent only to the mechanic's own email address, for the specific entry they performed. Each invitation can be used once and expires after 14 days. " \
      "If a mechanic forgets their password, the owner resets it or sends a new invitation; passwords are never shared or set on a mechanic's behalf. " \
      "Mechanics are encouraged to add an authenticator app. Accounts of mechanics no longer working on the aircraft are disabled at the next audit; their past signatures remain valid.",
      "**Account problems.** If someone may have used another person's password, or an account is locked without explanation, the owner disables or unlocks it as appropriate, " \
      "has the user change their password, and reviews the record history for changes made by that account. " \
      "An authenticator app is reset only after confirming the person's identity by phone or in person.",
      "**Share links.** Read-only share links are created only for a specific purpose (a mechanic, buyer, insurer or the FAA), with an expiry date where practical. " \
      "They are revoked when no longer needed and reviewed at each audit.",
      "**Retention (14 CFR 91.417(b)).** Records of maintenance, preventive maintenance and alterations, and of 100-hour, annual and progressive inspections, are kept until the work is " \
      "repeated or superseded, or for one year after it was performed. Total time in service, current status of life-limited parts, time since last overhaul, current inspection status " \
      "and AD status are kept permanently and transferred with the aircraft. In practice nothing is deleted: signed entries cannot be deleted, and the record history and off-site copies are kept.",
      "**Paper records.** The paper logbooks covering the period before #{since ? since.strftime('%B %-d, %Y') : '[the date electronic records began]'} are kept by the owner at [location] " \
      "and transferred with the aircraft. Their scans are marked as legacy records. Entries signed in ink after that date are scanned into Documents, and the paper is kept with the logbooks.",
      "**Shop visits.** When a shop prefers paper, entries are printed from the system for signature and the signed copy is scanned in. " \
      "A shop or the FAA may be given a time-limited Maintenance Detail share link for read-only access.",
      "**Sale of the aircraft.** The owner gives the buyer the paper logbooks and a records package from the system (the entries with their signatures, the record history, " \
      "the procedures and the data archive)."
    ].join("\n\n")
  end

  def https? = Rails.application.config.force_ssl

  def https_sentence
    if https?
      "Connections use HTTPS only: the system redirects plain HTTP and marks its cookies secure."
    else
      "The system is set not to enforce HTTPS itself (FORCE_SSL=false): [say how connections are protected, e.g. a TLS proxy in front, or the home network only]."
    end
  end

  def sign_in_sentence
    if Sso.enabled? && !Sso.password_login?
      "People sign in only with single sign-on (#{Sso.label}); password sign-in is turned off."
    elsif Sso.enabled?
      "People sign in with single sign-on (#{Sso.label}) or with their own email and password; there are no shared accounts."
    else
      "People sign in with their own email and password; there are no shared accounts."
    end
  end

  def docker? = File.exist?("/.dockerenv")
end
