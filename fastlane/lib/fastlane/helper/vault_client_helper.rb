require 'vault'
require 'base64'

module Fastlane
  module Helper
    class VaultClientHelper
      attr_reader :address
      attr_reader :token

      def initialize(address: nil, token: nil, vault_client: nil)
        @address = address
        @token = token

        @client = vault_client
      end

      def download_file(path)
        obj = Base64.decode64(client.logical.read(path))

        return obj
      end

      def upload_file(vault_path, file_path, file_data)
        split_path = vault_path.split("/", 2)
        print "HENLO\n"
        print vault_path
        print "HENLO\n"
        print file_path
        print "HENLO\n"
        print "repathed: #{split_path[0]}/data/#{split_path[1]}"
        print "HENLO\n"

        client.logical.write("#{split_path[0]}/data/#{split_path[1]}", "#{Base64.encode64(file_path)}": "#{Base64.encode64(file_data)}")
      end

      def delete_file(path)
        client.logical.delete(path)
      end

      def list_secrets!(path)
        obj = client.logical.list(path)

        return obj
      end

      private

      def client
        @client ||= Vault::Client.new(
          {
            address: address,
            token: token
          }.compact
        )
      end
    end
  end
end
