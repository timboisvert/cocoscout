class BackfillPublicKeysForPeople < ActiveRecord::Migration[8.1]
  def up
    # Backfill public_keys for existing Person records
    # Using raw SQL to avoid loading the entire model
    Person.find_each do |person|
      next if person.public_key.present?
      
      # Generate key from name: "firstname-lastname" or "firstname-lastname-id"
      base_key = person.name.parameterize
      key = base_key
      counter = 2
      
      # Check for uniqueness
      while Person.where(public_key: key).exists? || Group.where(public_key: key).exists?
        key = "#{base_key}-#{counter}"
        counter += 1
      end
      
      person.update_column(:public_key, key)
    end
  end

  def down
    # Not reversible - keys are permanent once assigned
    raise ActiveRecord::IrreversibleMigration
  end
end
