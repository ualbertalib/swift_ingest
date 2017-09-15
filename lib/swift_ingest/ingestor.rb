require 'swift_ingest/version'
require 'digest/md5'
require 'openstack'

class SwiftIngest::Ingestor

  attr_reader :swift_connection, :project

  def initialize(connection)
    @swift_connection = OpenStack::Connection.create(
      username: connection[:username],
      api_key: connection[:password],
      auth_method: 'password',
      auth_url: "#{connection[:endpoint]}/auth/#{connection[:auth_version]}",
      authtenant_name: connection[:tenant],
      service_type: 'object-store'
    )
    @project = connection[:project]
  end

  def deposit_file(file_name, swift_container)
    file_base_name = File.basename(file_name, '.*')

    checksum = Digest::MD5.file(file_name).hexdigest

    era_container = swift_connection.container(swift_container)

    # Add swift metadata with in accordance to AIP spec:
    # https://docs.google.com/document/d/154BqhDPAdGW-I9enrqLpBYbhkF9exX9lV3kMaijuwPg/edit#
    metadata = {
      project: @project,
      project_id: file_base_name,
      promise: 'bronze',
      aip_version: '1.0'
    }

    # ruby-openstack wants all keys of the metadata to be named like "X-Object-Meta-{{Key}}", so update them
    metadata.transform_keys! { |key| "X-Object-Meta-#{key}" }

    headers = { 'etag' => checksum,
                'content-type' => 'application/x-tar' }.merge(metadata)

    if era_container.object_exists?(file_base_name)
      deposited_file = era_container.object(file_base_name)
      deposited_file.write(File.open(file_name), headers)
    else
      deposited_file = era_container.create_object(file_base_name, headers, File.open(file_name))
    end

    deposited_file
  end

end
