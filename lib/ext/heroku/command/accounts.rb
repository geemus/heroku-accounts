# manage multiple heroku accounts
#
class Heroku::Command::Accounts < Heroku::Command::Base

  # accounts
  #
  # list all known accounts
  #
  def index
    display "No accounts found." if account_names.empty?

    current_account = Heroku::Auth.extract_account rescue nil

    account_names.each do |name|
      if name == current_account
        display "* #{name}"
      else
        display name
      end
    end
  end

  # accounts:add [NAME]
  #
  # add an account to the local credential store
  #
  # -a, --auto  # automatically generate an ssh key and add it to .ssh/config
  #
  def add
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account already exists.") if account_exists?(name)

    username, password = auth.ask_for_credentials

    write_account(name, [username, password])

    if extract_option("--auto") then
      display "Generating new SSH key"
      system %{ ssh-keygen -t rsa -f #{account_ssh_key(name)} -N "" }

      display "Adding entry to ~/.ssh/config"
      File.open(File.expand_path("~/.ssh/config"), "a") do |file|
        file.puts
        file.puts "Host heroku.#{name}"
        file.puts "  HostName heroku.com"
        file.puts "  IdentityFile #{account_ssh_key(name)}"
        file.puts "  IdentitiesOnly yes"
      end

      display "Adding public key to Heroku account: #{username}"
      client = Heroku::Client.new(username, password)
      client.add_key(File.read(File.expand_path(account_ssh_key(name) + ".pub")))
    else
      display ""
      display "Add the following to your ~/.ssh/config"
      display ""
      display "Host heroku.#{name}"
      display "  HostName heroku.com"
      display "  IdentityFile /PATH/TO/PRIVATE/KEY"
      display "  IdentitiesOnly yes"
    end
  end

  # accounts:remove
  #
  # remove an account from the local credential store
  #
  def remove
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account does not exist.") unless account_exists?(name)

    netrc.delete("api.#{host}.#{name}")
    netrc.delete("code.#{host}.#{name}")
    netrc.save

    display "Account removed: #{name}"
  end

  # accounts:set
  #
  # set the default account of an app
  #
  def set
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account does not exist.") unless account_exists?(name)

    %x{ git config heroku.account #{name} }

    git_remotes(Dir.pwd).each do |remote, app|
      %x{ git config remote.#{remote}.url git@heroku.#{name}:#{app}.git }
    end
  end

  # accounts:default
  #
  # set a system-wide default account
  #
  def default
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account does not exist.") unless account_exists?(name)

    # set base/default netrc entries
    netrc["api.#{host}"]  = netrc["api.#{host}.#{name}"]
    netrc["code.#{host}"] = netrc["code.#{host}.#{name}"]
    netrc.save

    %x{ git config --global heroku.account #{name} }
  end

## account interface #########################################################

  def self.account(name)
    accounts = Heroku::Command::Accounts.new(nil)
    accounts.send(:account, name)
  end

private ######################################################################

  def account(name)
    error("No such account: #{name}") unless account_exists?(name)
    username, password = netrc["api.#{host}.#{name}"]
    { :username => username, :password => password }
  end

  def account_names
    account_names = []
    netrc.each do |entry|
      if entry[1] =~ %r{api\.#{host}\.(.+)}
        account_names << $1
      end
    end
    account_names
  end

  def account_exists?(name)
    account_names.include?(name)
  end

  def account_ssh_key(name)
    File.expand_path("~/.ssh/identity.heroku.#{name}")
  end

  def auth
    if Heroku::VERSION < "2.0"
      Heroku::Command::Auth.new("")
    else
      Heroku::Auth
    end
  end

  def host
    Heroku::Auth.host
  end

  def netrc
    Heroku::Auth.netrc
  end

  def write_account(name, account)
    netrc["api.#{host}.#{name}"]  = account
    netrc["code.#{host}.#{name}"] = account
    netrc.save
  end

  def error(message)
    puts message
    exit 1
  end

end
