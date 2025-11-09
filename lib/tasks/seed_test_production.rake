namespace :seed do
  desc "Generate 60 test people with audition requests for production 14"
  task test_production: :environment do
    production = Production.find(14)
    production_company = production.production_company

    puts "Seeding test data for production: #{production.name} (ID: #{production.id})"

    # Create or find call to audition
    call_to_audition = production.call_to_audition
    unless call_to_audition
      call_to_audition = CallToAudition.create!(
        production: production,
        audition_type: :in_person,
        opens_at: 1.week.ago,
        closes_at: 1.week.from_now,
        form_reviewed: true,
        token: SecureRandom.hex(16)
      )
      puts "Created new call to audition"
    end

    # Create audition sessions
    location = production.production_company.locations.first || Location.create!(
      production_company: production_company,
      name: "Main Studio",
      address1: "123 Main St",
      city: "Los Angeles",
      state: "CA",
      postal_code: "90001"
    )

    sessions = []
    3.times do |i|
      session = AuditionSession.create!(
        production: production,
        call_to_audition: call_to_audition,
        location: location,
        start_at: 2.days.from_now + (i * 3).hours,
        end_at: 2.days.from_now + (i * 3 + 2).hours,
        maximum_auditionees: 20
      )
      sessions << session
      puts "Created audition session #{i + 1}: #{session.start_at.strftime('%A %B %d at %l:%M %p')}"
    end

    # Generate 60 test people with "TEST_" prefix for easy identification
    people = []
    60.times do |i|
      person = Person.create!(
        name: "TEST_Person_#{i + 1}",
        email: "test_person_#{i + 1}_#{Time.current.to_i}@example.com",
        pronouns: [ "he/him", "she/her", "they/them" ].sample
      )
      people << person
      puts "Created person #{i + 1}: #{person.name}"
    end

    # Create audition requests for all 60 people
    puts "\nCreating audition requests for all 60 people..."
    audition_requests = []
    people.each_with_index do |person, index|
      audition_request = AuditionRequest.create!(
        call_to_audition: call_to_audition,
        person: person,
        status: :unreviewed
      )
      audition_requests << audition_request
    end
    puts "Created #{audition_requests.count} audition requests"

    # Set first 30 to accepted status
    puts "\nSetting first 30 to accepted status..."
    accepted_requests = audition_requests.first(30)
    accepted_requests.each do |request|
      request.update(status: :accepted)
    end

    # Set remaining 30 to passed status
    puts "Setting remaining 30 to passed status..."
    passed_requests = audition_requests.last(30)
    passed_requests.each do |request|
      request.update(status: :passed)
    end

    # Schedule auditions for the 30 accepted people
    puts "\nScheduling auditions for accepted auditionees..."
    accepted_requests.each_with_index do |request, index|
      session = sessions[index % sessions.length]
      _audition = Audition.create!(
        person: request.person,
        audition_request: request,
        audition_session: session
      )
      puts "Scheduled audition for #{request.person.name} in session #{session.id}"
    end

    puts "\n✓ Test data seeding complete!"
    puts "\nSummary:"
    puts "- Production: #{production.name} (ID: 14)"
    puts "- Test people created: 60 (all with TEST_ prefix)"
    puts "- Call to audition: #{call_to_audition.id}"
    puts "- Audition sessions created: #{sessions.count}"
    puts "- Audition requests: 60 total"
    puts "  - Accepted (30): Will have auditions scheduled"
    puts "  - Passed/Rejected (30): No auditions scheduled"
    puts "\nTo delete all test data later, run:"
    puts "  Person.where(\"name LIKE ?\", \"TEST_%\").destroy_all"
    puts "\nTest data pages:"
    puts "  - Review: http://localhost:3000/manage/productions/14/auditions/review"
    puts "  - Run Auditions: http://localhost:3000/manage/productions/14/auditions/run"
    puts "  - Casting: http://localhost:3000/manage/productions/14/auditions/casting"
  end
end
