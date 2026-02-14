class UpdateContractServicesNames < ActiveRecord::Migration[8.1]
  def up
    # Mapping of old service names to new names
    name_mapping = {
      "Tech support" => "Lighting/Audio",
      "Box office" => "Ticketing",
      "Concessions" => "Bar"
    }

    Contract.find_each do |contract|
      services = contract.draft_data["services"]
      next if services.blank?

      updated_services = services.map do |service|
        old_name = service["name"]
        new_name = name_mapping[old_name]

        if new_name
          service.merge("name" => new_name)
        else
          service
        end
      end

      new_draft_data = contract.draft_data.merge("services" => updated_services)
      contract.update_column(:draft_data, new_draft_data)
    end
  end

  def down
    # Reverse mapping
    name_mapping = {
      "Lighting/Audio" => "Tech support",
      "Ticketing" => "Box office",
      "Bar" => "Concessions"
    }

    Contract.find_each do |contract|
      services = contract.draft_data["services"]
      next if services.blank?

      updated_services = services.map do |service|
        old_name = service["name"]
        new_name = name_mapping[old_name]

        if new_name
          service.merge("name" => new_name)
        else
          service
        end
      end

      new_draft_data = contract.draft_data.merge("services" => updated_services)
      contract.update_column(:draft_data, new_draft_data)
    end
  end
end
