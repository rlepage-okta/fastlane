require 'fastlane_core/command_executor'
require 'fastlane_core/configuration/configuration'
require 'fastlane/helper/vault_client_helper'

require_relative '../options'
require_relative '../module'
require_relative '../spaceship_ensure'
require_relative './interface'

module Match
  module Storage
    # Store the code signing identities on AWS S3
    class VaultStorage < Interface
      attr_reader :vault_address
      attr_reader :vault_token
      attr_reader :vault_path
      attr_reader :vault_client
      attr_reader :readonly
      attr_reader :username
      attr_reader :team_id
      attr_reader :team_name
      attr_reader :api_key_path
      attr_reader :api_key

      def self.configure(params)
        vault_address = params[:vault_address]
        vault_token = params[:vault_token]
        vault_path = params[:vault_path]

        if params[:git_url].to_s.length > 0
          UI.important("Looks like you still define a `git_url` somewhere, even though")
          UI.important("you use Vault Storage. You can remove the `git_url`")
          UI.important("from your Matchfile and Fastfile")
          UI.message("The above is just a warning, fastlane will continue as usual now...")
        end

        return self.new(
          vault_address: vault_address,
          vault_token: vault_token,
          vault_path: vault_path,
          readonly: params[:readonly],
          username: params[:username],
          team_id: params[:team_id],
          team_name: params[:team_name],
          api_key_path: params[:api_key_path],
          api_key: params[:api_key]
        )
      end

      def initialize(vault_address: nil,
                     vault_token: nil,
                     vault_path: nil,
                     readonly: nil,
                     username: nil,
                     team_id: nil,
                     team_name: nil,
                     api_key_path: nil,
                     api_key: nil)
        @vault_path = vault_path
        @vault_client = Fastlane::Helper::VaultClientHelper.new(address: vault_address, token: vault_token)
        @readonly = readonly
        @username = username
        @team_id = team_id
        @team_name = team_name
        @api_key_path = api_key_path
        @api_key = api_key
      end

      # To make debugging easier, we have a custom exception here
      def prefixed_working_directory
        # We fall back to "*", which means certificates and profiles
        # from all teams that use this bucket would be installed. This is not ideal, but
        # unless the user provides a `team_id`, we can't know which one to use
        # This only happens if `readonly` is activated, and no `team_id` was provided
        @_folder_prefix ||= currently_used_team_id
        if @_folder_prefix.nil?
          # We use a `@_folder_prefix` variable, to keep state between multiple calls of this
          # method, as the value won't change. This way the warning is only printed once
          UI.important("Looks like you run `match` in `readonly` mode, and didn't provide a `team_id`. This will still work, however it is recommended to provide a `team_id` in your Appfile or Matchfile")
          @_folder_prefix = "*"
        end
        return File.join(working_directory, @_folder_prefix)
      end

      # Call this method for the initial clone/download of the
      # user's certificates & profiles
      # As part of this method, the `self.working_directory` attribute
      # will be set
      def download
        # Check if we already have a functional working_directory
        return if @working_directory && Dir.exist?(@working_directory)

        # No existing working directory, creating a new one now
        self.working_directory = Dir.mktmpdir

        vault_client.list_secrets!(vault_path).each do |object|
          file_path = object.name # e.g. "N8X438SEU2/certs/distribution/XD9G7QCACF.cer"

          download_path = File.join(self.working_directory, file_path)

          FileUtils.mkdir_p(File.expand_path("..", download_path))
          UI.verbose("Downloading file from Vault '#{file_path}' on path #{self.vault_path}")

          object.download_file(download_path)
        end
        UI.verbose("Successfully downloaded files from Vault to #{self.working_directory}")
      end

      # Returns a short string describing + identifing the current
      # storage backend. This will be printed when nuking a storage
      def human_readable_description
        return "Vault path [#{vault_path}]"
      end

      def upload_files(files_to_upload: [], custom_message: nil)
        # `files_to_upload` is an array of files that need to be uploaded to Vault
        # Those doesn't mean they're new, it might just be they're changed
        # Either way, we'll upload them using the same technique

        files_to_upload.each do |current_file|
          # Go from
          #   "/var/folders/px/bz2kts9n69g8crgv4jpjh6b40000gn/T/d20181026-96528-1av4gge/:team_id/profiles/development/Development_me.mobileprovision"
          # to
          #   "profiles/development/Development_me.mobileprovision"
          #
          target_path = current_file.gsub(self.working_directory, "")
          UI.verbose("Uploading '#{target_path}' to Vault Storage...")
          vault_client.upload_file(target_path, current_file)
        end
      end

      def delete_files(files_to_delete: [], custom_message: nil)
        files_to_delete.each do |current_file|
          target_path = current_file.gsub(self.working_directory, "")
          UI.verbose("Deleting '#{target_path}' from Vault Storage...")
          vault_client.delete_file(target_path)
        end
      end

      def skip_docs
        false
      end

      def list_files(file_name: "", file_ext: "")
        Dir[File.join(working_directory, self.team_id, "**", file_name, "*.#{file_ext}")]
      end

      # Implement this for the `fastlane match init` command
      # This method must return the content of the Matchfile
      # that should be generated
      def generate_matchfile_content(template: nil)
        return "vault_bucket(\"#{self.vault_path}\")"
      end

      private

      def currently_used_team_id
        if self.readonly
          # In readonly mode, we still want to see if the user provided a team_id
          # see `prefixed_working_directory` comments for more details
          return self.team_id
        else
          UI.user_error!("The `team_id` option is required. fastlane cannot automatically determine portal team id via the App Store Connect API (yet)") if self.team_id.to_s.empty?

          spaceship = SpaceshipEnsure.new(self.username, self.team_id, self.team_name, api_token)
          return spaceship.team_id
        end
      end

      def api_token
        api_token = Spaceship::ConnectAPI::Token.from(hash: self.api_key, filepath: self.api_key_path)
        api_token ||= Spaceship::ConnectAPI.token
        return api_token
      end
    end
  end
end
