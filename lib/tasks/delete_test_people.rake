namespace :seed do
  desc "Delete all TEST people and their associated records"
  task delete_test_people: :environment do
    # Find people with TEST at the end of their name or TEST_ at the beginning
    test_people = Person.where("name LIKE ? OR name LIKE ?", "%TEST", "TEST%")

    puts "Found #{test_people.count} TEST people to delete"

    count = 0
    test_people.each do |person|
      puts "Deleting #{person.name}..."

      # Manually delete associated records to avoid foreign key constraints
      ActiveRecord::Base.transaction do
        # Delete cast assignment stages
        CastAssignmentStage.where(person_id: person.id).delete_all

        # Delete show person role assignments
        ShowPersonRoleAssignment.where(person_id: person.id).delete_all

        # Delete show availabilities
        ShowAvailability.where(person_id: person.id).delete_all

        # Delete auditions (which will cascade to audition requests via dependent: :destroy)
        Audition.where(person_id: person.id).delete_all

        # Delete audition requests (which will cascade to answers)
        AuditionRequest.where(person_id: person.id).destroy_all

        # Remove from production company associations
        person.production_companies.clear

        # Remove from casts
        person.casts.clear

        # Now delete the person
        person.destroy

        count += 1
      end
    rescue => e
      puts "  Error deleting #{person.name}: #{e.message}"
      puts "  Continuing with next person..."
    end

    puts "\n✓ Deleted #{count} TEST people"
  end
end
