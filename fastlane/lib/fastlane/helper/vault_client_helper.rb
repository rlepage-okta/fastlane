require 'vault'

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
        obj = client.logical.read(path)

        return obj
      end

      def upload_file(path, file_data)
        client.logical.write(path, file_data)
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
