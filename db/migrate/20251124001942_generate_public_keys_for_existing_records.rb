class GeneratePublicKeysForExistingRecords < ActiveRecord::Migration[8.1]
  def up
    # Generate public keys for people without them
    Person.where(public_key: nil).find_each do |person|
      base_key = person.name.present? ? person.name.parameterize : "person"
      key = base_key
      counter = 1

      # Ensure uniqueness
      while Person.where(public_key: key).exists? || Group.where(public_key: key).exists?
        key = "#{base_key}-#{counter}"
        counter += 1
      end

      person.update_column(:public_key, key)
    end

    # Generate public keys for groups without them
    Group.where(public_key: nil).find_each do |group|
      base_key = group.name.present? ? group.name.parameterize : "group"
      key = base_key
      counter = 1

      # Ensure uniqueness
      while Person.where(public_key: key).exists? || Group.where(public_key: key).exists?
        key = "#{base_key}-#{counter}"
        counter += 1
      end

      group.update_column(:public_key, key)
    end
  end

  def down
    # No need to reverse this migration
  end
end
