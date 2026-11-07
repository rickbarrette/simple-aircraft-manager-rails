# Account recovery from the command line (see AccountRecovery). In Docker:
#   docker compose exec web bin/rails users:list
#   docker compose exec web bin/rails "users:reset_password[jane@example.com]"
namespace :users do
  run = lambda do |&block|
    block.call
  rescue AccountRecovery::Error => e
    abort "Error: #{e.message}"
  end

  desc "List accounts with their admin, disabled, locked, 2FA and SSO status"
  task list: :environment do
    puts AccountRecovery.list
  end

  desc "Set a new password (PASSWORD=... or a generated one, shown once), unlock, and sign out everywhere"
  task :reset_password, [ :email ] => :environment do |_, args|
    run.call do
      password = AccountRecovery.reset_password!(args[:email], password: ENV["PASSWORD"])
      puts "New password for #{args[:email]}: #{password}"
      puts "Signed out everywhere and unlocked. Change it after signing in (Profile)." unless ENV["PASSWORD"].present?
    end
  end

  desc "Print a one-time sign-in link (15 minutes), for when email isn't working"
  task :sign_in_link, [ :email ] => :environment do |_, args|
    run.call { puts AccountRecovery.sign_in_link(args[:email]), "Works once, for 15 minutes. If the account has two-factor on, it still asks for the code." }
  end

  desc "Clear a lockout after failed sign-ins"
  task :unlock, [ :email ] => :environment do |_, args|
    run.call { AccountRecovery.unlock!(args[:email]) && puts("Unlocked #{args[:email]}.") }
  end

  desc "Turn off the authenticator app (lost phone and recovery codes)"
  task :reset_two_factor, [ :email ] => :environment do |_, args|
    run.call { AccountRecovery.reset_two_factor!(args[:email]) && puts("Two-factor turned off for #{args[:email]}. They can set it up again from their profile.") }
  end

  desc "Enable a disabled account"
  task :enable, [ :email ] => :environment do |_, args|
    run.call { AccountRecovery.enable!(args[:email]) && puts("Enabled #{args[:email]}.") }
  end

  desc "Disable an account and sign it out everywhere"
  task :disable, [ :email ] => :environment do |_, args|
    run.call { AccountRecovery.disable!(args[:email]) && puts("Disabled #{args[:email]}.") }
  end

  desc "Make an existing account an admin"
  task :make_admin, [ :email ] => :environment do |_, args|
    run.call do
      AccountRecovery.make_admin!(args[:email])
      puts "#{args[:email]} is now an admin."
      puts "Note: OIDC_ADMIN_GROUP is set, so their next single sign-on sign-in sets admin from the group again." if Sso.admin_group
    end
  end

  desc "Create a new admin account (PASSWORD=... or a generated one)"
  task :create_admin, [ :email, :name ] => :environment do |_, args|
    run.call do
      user, password = AccountRecovery.create_admin!(args[:email], name: args[:name], password: ENV["PASSWORD"])
      puts "Created admin #{user.email_address} with password: #{password}"
    end
  end
end
