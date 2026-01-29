# frozen_string_literal: true

# =============================================================================
# DEMO DATA SEEDING SCRIPT
# =============================================================================
#
# Creates a complete demo organization with realistic data for:
# - Investor demos
# - Public demo environment
# - Marketing screenshots
#
# USAGE:
#   rails demo:seed              # Create/reset demo data
#   rails demo:destroy           # Remove all demo data
#
# CREDENTIALS:
#   All demo users have password: Password1!
#   Demo admin email: demo@cocoscout.com
#
# DEMO ORGANIZATION: "Starlight Community Theater"
#   - 6 in-house productions
#   - 6 space rental contracts
#   - 25+ performers in talent pools
#   - Full casting, availability, auditions, sign-ups
#   - Complete money/payout configuration
#
# =============================================================================

namespace :demo do
  desc "Destroy all demo data"
  task destroy: :environment do
    DemoSeeder.destroy_all
  end

  desc "Seed complete demo organization"
  task seed: :environment do
    DemoSeeder.seed_all
  end
end

class DemoSeeder
  DEMO_ORG_NAME = "Starlight Community Theater"
  DEMO_EMAIL_DOMAIN = "demo.cocoscout.com"
  DEMO_PASSWORD = "Password1!"

  # Performer names (realistic mix)
  PERFORMER_NAMES = [
    { first: "Sarah", last: "Mitchell", pronouns: "she/her" },
    { first: "James", last: "Rodriguez", pronouns: "he/him" },
    { first: "Emily", last: "Chen", pronouns: "she/her" },
    { first: "Michael", last: "Thompson", pronouns: "he/him" },
    { first: "Jessica", last: "Williams", pronouns: "she/her" },
    { first: "David", last: "Kim", pronouns: "he/him" },
    { first: "Amanda", last: "Foster", pronouns: "she/her" },
    { first: "Christopher", last: "Davis", pronouns: "he/him" },
    { first: "Rachel", last: "Martinez", pronouns: "she/her" },
    { first: "Andrew", last: "Wilson", pronouns: "he/him" },
    { first: "Lauren", last: "Taylor", pronouns: "she/her" },
    { first: "Daniel", last: "Anderson", pronouns: "he/him" },
    { first: "Megan", last: "Brown", pronouns: "she/her" },
    { first: "Joshua", last: "Garcia", pronouns: "he/him" },
    { first: "Ashley", last: "Moore", pronouns: "she/her" },
    { first: "Ryan", last: "Jackson", pronouns: "he/him" },
    { first: "Samantha", last: "White", pronouns: "she/her" },
    { first: "Justin", last: "Harris", pronouns: "he/him" },
    { first: "Nicole", last: "Clark", pronouns: "she/her" },
    { first: "Brandon", last: "Lewis", pronouns: "he/him" },
    { first: "Taylor", last: "Robinson", pronouns: "they/them" },
    { first: "Jordan", last: "Walker", pronouns: "they/them" },
    { first: "Alex", last: "Hall", pronouns: "they/them" },
    { first: "Morgan", last: "Young", pronouns: "she/her" },
    { first: "Casey", last: "King", pronouns: "he/him" }
  ].freeze

  # Headshot URLs from randomuser.me (placeholder images)
  HEADSHOT_URLS = {
    female: [
      "https://randomuser.me/api/portraits/women/1.jpg",
      "https://randomuser.me/api/portraits/women/2.jpg",
      "https://randomuser.me/api/portraits/women/3.jpg",
      "https://randomuser.me/api/portraits/women/4.jpg",
      "https://randomuser.me/api/portraits/women/5.jpg",
      "https://randomuser.me/api/portraits/women/6.jpg",
      "https://randomuser.me/api/portraits/women/7.jpg",
      "https://randomuser.me/api/portraits/women/8.jpg",
      "https://randomuser.me/api/portraits/women/9.jpg",
      "https://randomuser.me/api/portraits/women/10.jpg",
      "https://randomuser.me/api/portraits/women/11.jpg",
      "https://randomuser.me/api/portraits/women/12.jpg",
      "https://randomuser.me/api/portraits/women/13.jpg",
      "https://randomuser.me/api/portraits/women/14.jpg",
      "https://randomuser.me/api/portraits/women/15.jpg"
    ],
    male: [
      "https://randomuser.me/api/portraits/men/1.jpg",
      "https://randomuser.me/api/portraits/men/2.jpg",
      "https://randomuser.me/api/portraits/men/3.jpg",
      "https://randomuser.me/api/portraits/men/4.jpg",
      "https://randomuser.me/api/portraits/men/5.jpg",
      "https://randomuser.me/api/portraits/men/6.jpg",
      "https://randomuser.me/api/portraits/men/7.jpg",
      "https://randomuser.me/api/portraits/men/8.jpg",
      "https://randomuser.me/api/portraits/men/9.jpg",
      "https://randomuser.me/api/portraits/men/10.jpg"
    ],
    neutral: [
      "https://randomuser.me/api/portraits/lego/1.jpg",
      "https://randomuser.me/api/portraits/lego/2.jpg",
      "https://randomuser.me/api/portraits/lego/3.jpg"
    ]
  }.freeze

  class << self
    def destroy_all
      puts "=" * 60
      puts "DESTROYING DEMO DATA"
      puts "=" * 60

      org = Organization.find_by(name: DEMO_ORG_NAME)
      if org.nil?
        puts "No demo organization found. Nothing to destroy."
        return
      end

      # Find all demo users (by email domain)
      demo_users = User.where("email_address LIKE ?", "%@#{DEMO_EMAIL_DOMAIN}")

      # Destroy organization (cascades to productions, shows, etc.)
      puts "Destroying organization: #{org.name}..."
      org.destroy!

      # Destroy demo users
      puts "Destroying #{demo_users.count} demo users..."
      demo_users.destroy_all

      # Clean up any orphaned people without users that were in the demo org
      # (People are not dependent: :destroy on organization)
      orphaned_people = Person.left_joins(:user).where(users: { id: nil })
                              .where("email LIKE ?", "%@#{DEMO_EMAIL_DOMAIN}")
      puts "Cleaning up #{orphaned_people.count} orphaned demo people..."
      orphaned_people.destroy_all

      puts "Demo data destroyed successfully!"
    end

    def seed_all
      puts "=" * 60
      puts "SEEDING DEMO DATA"
      puts "Demo organization: #{DEMO_ORG_NAME}"
      puts "All passwords: #{DEMO_PASSWORD}"
      puts "=" * 60

      # Destroy existing demo data first
      destroy_all

      ActiveRecord::Base.transaction do
        @created_people = []
        @created_users = []

        create_admin_user
        create_organization
        create_locations
        create_manager_users
        create_performer_users_and_people
        create_groups
        create_in_house_productions
        create_space_rental_contracts
        create_shows_and_casting
        create_availability
        create_open_mic_with_signups
        create_audition_cycle
        create_financials_and_payouts

        print_summary
      end
    end

    private

    def create_admin_user
      puts "\nCreating admin user..."
      @admin_user = User.create!(
        email_address: "demo@#{DEMO_EMAIL_DOMAIN}",
        password: DEMO_PASSWORD,
        password_confirmation: DEMO_PASSWORD
      )
      @created_users << @admin_user
      puts "  Created: #{@admin_user.email_address}"
    end

    def create_organization
      puts "\nCreating organization..."
      @org = Organization.create!(
        name: DEMO_ORG_NAME,
        owner: @admin_user,
        talent_pool_mode: "per_production",
        forum_mode: "per_production"
      )

      # Add admin as manager
      OrganizationRole.create!(
        organization: @org,
        user: @admin_user,
        role: "manager"
      )

      puts "  Created: #{@org.name}"
    end

    def create_locations
      puts "\nCreating locations..."

      @main_location = Location.create!(
        organization: @org,
        name: "Starlight Theater",
        address1: "123 Main Street",
        city: "Springfield",
        state: "IL",
        postal_code: "62701",
        default: true
      )

      # Create spaces
      @main_stage = LocationSpace.create!(
        location: @main_location,
        name: "Main Stage",
        capacity: 300,
        default: true,
        description: "Our primary performance space with full theatrical lighting and sound."
      )

      @black_box = LocationSpace.create!(
        location: @main_location,
        name: "Black Box Theater",
        capacity: 100,
        description: "Flexible intimate performance space."
      )

      @rehearsal_a = LocationSpace.create!(
        location: @main_location,
        name: "Rehearsal Room A",
        capacity: 30,
        description: "Large rehearsal space with mirrors and piano."
      )

      @rehearsal_b = LocationSpace.create!(
        location: @main_location,
        name: "Rehearsal Room B",
        capacity: 20,
        description: "Standard rehearsal room."
      )

      @lobby = LocationSpace.create!(
        location: @main_location,
        name: "Lobby & Event Space",
        capacity: 150,
        description: "Multi-purpose space for receptions and events."
      )

      puts "  Created: #{@main_location.name} with #{@main_location.location_spaces.count} spaces"
    end

    def create_manager_users
      puts "\nCreating manager users..."

      managers = [
        { name: "Jennifer Hayes", title: "Artistic Director" },
        { name: "Marcus Johnson", title: "Production Manager" }
      ]

      @manager_users = managers.map do |mgr|
        email = mgr[:name].downcase.gsub(" ", ".") + "@#{DEMO_EMAIL_DOMAIN}"
        user = User.create!(
          email_address: email,
          password: DEMO_PASSWORD,
          password_confirmation: DEMO_PASSWORD
        )

        OrganizationRole.create!(
          organization: @org,
          user: user,
          role: "manager"
        )

        # Create person profile for manager
        person = create_person(
          user: user,
          name: mgr[:name],
          email: email,
          bio: "#{mgr[:title]} at #{DEMO_ORG_NAME}."
        )

        @created_users << user
        puts "  Created manager: #{email}"
        user
      end
    end

    def create_performer_users_and_people
      puts "\nCreating performer users and profiles..."

      female_headshot_idx = 0
      male_headshot_idx = 0
      neutral_headshot_idx = 0

      PERFORMER_NAMES.each_with_index do |performer, idx|
        full_name = "#{performer[:first]} #{performer[:last]}"
        email = "#{performer[:first].downcase}.#{performer[:last].downcase}@#{DEMO_EMAIL_DOMAIN}"

        user = User.create!(
          email_address: email,
          password: DEMO_PASSWORD,
          password_confirmation: DEMO_PASSWORD
        )

        OrganizationRole.create!(
          organization: @org,
          user: user,
          role: "member"
        )

        # Determine headshot based on pronouns
        headshot_url = case performer[:pronouns]
        when "she/her"
          url = HEADSHOT_URLS[:female][female_headshot_idx % HEADSHOT_URLS[:female].length]
          female_headshot_idx += 1
          url
        when "he/him"
          url = HEADSHOT_URLS[:male][male_headshot_idx % HEADSHOT_URLS[:male].length]
          male_headshot_idx += 1
          url
        else
          url = HEADSHOT_URLS[:neutral][neutral_headshot_idx % HEADSHOT_URLS[:neutral].length]
          neutral_headshot_idx += 1
          url
        end

        person = create_person(
          user: user,
          name: full_name,
          email: email,
          pronouns: performer[:pronouns],
          bio: generate_performer_bio(performer),
          headshot_url: headshot_url
        )

        # Give some people multiple profiles (performers 0 and 5)
        if idx == 0
          # Sarah Mitchell also performs as "Sally Mae" (stage name)
          alt_person = create_person(
            user: user,
            name: "Sally Mae",
            email: email,
            pronouns: performer[:pronouns],
            bio: "Stage name for #{full_name}. Specializes in country and folk performances.",
            headshot_url: HEADSHOT_URLS[:female][female_headshot_idx % HEADSHOT_URLS[:female].length]
          )
          female_headshot_idx += 1
          puts "    Also created alternate profile: Sally Mae"
        elsif idx == 5
          # David Kim also has a comedy persona
          alt_person = create_person(
            user: user,
            name: "Dave K. Comedy",
            email: email,
            pronouns: performer[:pronouns],
            bio: "Comedy persona for #{full_name}. Stand-up and improv specialist.",
            headshot_url: HEADSHOT_URLS[:male][male_headshot_idx % HEADSHOT_URLS[:male].length]
          )
          male_headshot_idx += 1
          puts "    Also created alternate profile: Dave K. Comedy"
        end

        @created_users << user
        print "." if idx % 5 == 0
      end

      puts "\n  Created #{PERFORMER_NAMES.count} performers with profiles"
    end

    def create_person(user:, name:, email:, pronouns: nil, bio: nil, headshot_url: nil)
      person = Person.create!(
        user: user,
        name: name,
        email: email,
        pronouns: pronouns,
        bio: bio,
        phone: generate_phone_number
      )

      # Associate with organization
      @org.people << person unless @org.people.include?(person)

      # Set as default person if user doesn't have one
      user.update!(default_person: person) if user.default_person.nil?

      # Attach headshot if URL provided
      if headshot_url
        attach_headshot(person, headshot_url)
      end

      # Add some skills
      add_random_skills(person)

      # Add performance credits
      add_performance_credits(person)

      @created_people << person
      person
    end

    def attach_headshot(person, url)
      # Download and attach the image
      require "open-uri"
      begin
        file = URI.open(url)
        filename = "headshot_#{person.id}.jpg"

        headshot = person.profile_headshots.create!(
          is_primary: true,
          category: "theatrical"
        )
        headshot.image.attach(io: file, filename: filename, content_type: "image/jpeg")
      rescue StandardError => e
        puts "    Warning: Could not attach headshot for #{person.name}: #{e.message}"
      end
    end

    def add_random_skills(person)
      skill_categories = {
        "Vocal Range" => [ "Soprano", "Mezzo-Soprano", "Alto", "Tenor", "Baritone", "Bass" ],
        "Dance" => [ "Ballet", "Jazz", "Tap", "Contemporary", "Hip Hop", "Ballroom" ],
        "Instruments" => [ "Piano", "Guitar", "Violin", "Drums", "Flute", "Saxophone" ],
        "Accents" => [ "British", "Southern", "New York", "Boston", "Irish", "French" ],
        "Special Skills" => [ "Stage Combat", "Juggling", "Tumbling", "Puppetry", "Sign Language" ]
      }

      # Add 3-6 random skills
      num_skills = rand(3..6)
      categories = skill_categories.keys.sample(num_skills)

      categories.each do |category|
        skill = skill_categories[category].sample
        ProfileSkill.create!(
          profileable: person,
          category: category,
          skill_name: skill
        )
      end
    end

    def add_performance_credits(person)
      credits = [
        { title: "Les Misérables", role: "Ensemble", location: "Community Playhouse" },
        { title: "Grease", role: "Rizzo", location: "Summer Stock Theater" },
        { title: "Romeo and Juliet", role: "Nurse", location: "Shakespeare in the Park" },
        { title: "The Wizard of Oz", role: "Dorothy", location: "Youth Theater" },
        { title: "Rent", role: "Mark", location: "Off-Broadway Tour" },
        { title: "Chicago", role: "Velma Kelly", location: "Regional Theater" },
        { title: "A Chorus Line", role: "Cassie", location: "Dinner Theater" },
        { title: "Hairspray", role: "Tracy Turnblad", location: "High School" }
      ]

      # Add 2-4 random credits
      num_credits = rand(2..4)
      selected_credits = credits.sample(num_credits)

      selected_credits.each_with_index do |credit, idx|
        PerformanceCredit.create!(
          profileable: person,
          title: credit[:title],
          role: credit[:role],
          location: credit[:location],
          year_start: rand(2018..2024),
          position: idx
        )
      end
    end

    def create_groups
      puts "\nCreating performance groups..."

      # Create an improv troupe
      @improv_troupe = Group.create!(
        name: "The Spontaneous Players",
        email: "spontaneous@#{DEMO_EMAIL_DOMAIN}",
        bio: "Award-winning improv comedy troupe performing weekly at Starlight Theater."
      )
      @org.groups << @improv_troupe

      # Add 5 members to the improv troupe
      improv_members = @created_people.sample(5)
      improv_members.each do |person|
        GroupMembership.create!(group: @improv_troupe, person: person)
      end

      # Create a jazz ensemble
      @jazz_ensemble = Group.create!(
        name: "Starlight Jazz Trio",
        email: "jazz@#{DEMO_EMAIL_DOMAIN}",
        bio: "House jazz ensemble providing live music for events and performances."
      )
      @org.groups << @jazz_ensemble

      # Add 3 members
      jazz_members = (@created_people - improv_members).sample(3)
      jazz_members.each do |person|
        GroupMembership.create!(group: @jazz_ensemble, person: person)
      end

      puts "  Created: #{@improv_troupe.name} (#{improv_members.count} members)"
      puts "  Created: #{@jazz_ensemble.name} (#{jazz_members.count} members)"
    end

    def create_in_house_productions
      puts "\nCreating in-house productions..."

      # Production 1: The Sound of Music (Musical)
      @sound_of_music = create_production(
        name: "The Sound of Music",
        description: "Rodgers and Hammerstein's beloved musical about the von Trapp family.",
        roles: [
          { name: "Maria", quantity: 1, category: "performing" },
          { name: "Captain von Trapp", quantity: 1, category: "performing" },
          { name: "Baroness Schraeder", quantity: 1, category: "performing" },
          { name: "Max Detweiler", quantity: 1, category: "performing" },
          { name: "Mother Abbess", quantity: 1, category: "performing" },
          { name: "Liesl", quantity: 1, category: "performing" },
          { name: "Friedrich", quantity: 1, category: "performing" },
          { name: "Louisa", quantity: 1, category: "performing" },
          { name: "Kurt", quantity: 1, category: "performing" },
          { name: "Brigitta", quantity: 1, category: "performing" },
          { name: "Marta", quantity: 1, category: "performing" },
          { name: "Gretl", quantity: 1, category: "performing" },
          { name: "Ensemble", quantity: 8, category: "performing" },
          { name: "Stage Manager", quantity: 1, category: "technical" },
          { name: "Lighting Operator", quantity: 1, category: "technical" }
        ],
        talent_pool_size: 15
      )

      # Production 2: A Midsummer Night's Dream (Shakespeare)
      @midsummer = create_production(
        name: "A Midsummer Night's Dream",
        description: "Shakespeare's enchanting comedy of love, magic, and mischief.",
        roles: [
          { name: "Puck", quantity: 1, category: "performing" },
          { name: "Oberon", quantity: 1, category: "performing" },
          { name: "Titania", quantity: 1, category: "performing" },
          { name: "Bottom", quantity: 1, category: "performing" },
          { name: "Lysander", quantity: 1, category: "performing" },
          { name: "Demetrius", quantity: 1, category: "performing" },
          { name: "Hermia", quantity: 1, category: "performing" },
          { name: "Helena", quantity: 1, category: "performing" },
          { name: "Theseus", quantity: 1, category: "performing" },
          { name: "Hippolyta", quantity: 1, category: "performing" },
          { name: "Mechanicals", quantity: 4, category: "performing" },
          { name: "Fairies", quantity: 4, category: "performing" },
          { name: "Stage Manager", quantity: 1, category: "technical" }
        ],
        talent_pool_size: 12
      )

      # Production 3: Chicago (Musical) - shares talent pool with Sound of Music
      @chicago = create_production(
        name: "Chicago",
        description: "The Tony Award-winning musical about murder, greed, corruption, and all that jazz.",
        roles: [
          { name: "Roxie Hart", quantity: 1, category: "performing" },
          { name: "Velma Kelly", quantity: 1, category: "performing" },
          { name: "Billy Flynn", quantity: 1, category: "performing" },
          { name: "Matron 'Mama' Morton", quantity: 1, category: "performing" },
          { name: "Amos Hart", quantity: 1, category: "performing" },
          { name: "Mary Sunshine", quantity: 1, category: "performing" },
          { name: "Merry Murderesses", quantity: 6, category: "performing" },
          { name: "Ensemble", quantity: 6, category: "performing" },
          { name: "Stage Manager", quantity: 1, category: "technical" },
          { name: "Choreographer Assistant", quantity: 1, category: "technical" }
        ],
        talent_pool_size: 14,
        share_talent_pool_with: @sound_of_music
      )

      # Production 4: Open Mic Night (Weekly with sign-up)
      @open_mic = create_production(
        name: "Open Mic Night",
        description: "Weekly showcase for local performers. Sign up to share your talent!",
        casting_source: "sign_up",
        roles: [
          { name: "Performer", quantity: 12, category: "performing" },
          { name: "Host", quantity: 1, category: "performing" },
          { name: "Sound Tech", quantity: 1, category: "technical" }
        ],
        talent_pool_size: 0  # Sign-up based, no talent pool needed
      )

      # Production 5: Improv Workshop Series (Weekly class)
      @improv_workshop = create_production(
        name: "Improv Workshop Series",
        description: "Weekly improv comedy workshops for all skill levels.",
        roles: [
          { name: "Instructor", quantity: 1, category: "performing" },
          { name: "Participant", quantity: 15, category: "performing" }
        ],
        talent_pool_size: 10
      )

      # Production 6: Spring Showcase (One-off with auditions)
      @spring_showcase = create_production(
        name: "Spring Showcase",
        description: "Annual showcase featuring the best local talent. Auditions required.",
        roles: [
          { name: "Featured Performer", quantity: 8, category: "performing" },
          { name: "Ensemble", quantity: 12, category: "performing" },
          { name: "Stage Manager", quantity: 1, category: "technical" },
          { name: "Lighting Designer", quantity: 1, category: "technical" }
        ],
        talent_pool_size: 0  # Will use auditions
      )

      puts "  Created 6 in-house productions"
    end

    def create_production(name:, description:, roles:, talent_pool_size:, casting_source: "talent_pool", share_talent_pool_with: nil)
      production = Production.create!(
        organization: @org,
        name: name,
        description: description,
        production_type: "in_house",
        casting_source: casting_source,
        forum_enabled: true,
        show_cast_members: true
      )

      # Create roles
      roles.each_with_index do |role_attrs, idx|
        Role.create!(
          production: production,
          name: role_attrs[:name],
          quantity: role_attrs[:quantity],
          category: role_attrs[:category],
          position: idx
        )
      end

      # Create talent pool
      if talent_pool_size > 0
        talent_pool = TalentPool.create!(
          production: production,
          name: "#{name} Talent Pool"
        )

        # Add people to talent pool
        pool_members = @created_people.sample(talent_pool_size)
        pool_members.each do |person|
          TalentPoolMembership.create!(
            talent_pool: talent_pool,
            member: person
          )
        end

        # Share talent pool if specified
        if share_talent_pool_with
          TalentPoolShare.create!(
            talent_pool: share_talent_pool_with.talent_pools.first,
            production: production
          )
        end
      end

      production
    end

    def create_space_rental_contracts
      puts "\nCreating space rental contracts..."

      # Contract 1: Hamilton Jr. - Youth Theater
      @hamilton_jr_contract = create_contract(
        contractor_name: "Springfield Youth Theater",
        contractor_email: "director@springfieldyouth.org",
        contractor_phone: "2175551234",
        production_name: "Hamilton Jr.",
        services: [ "Main Stage rental", "Lighting package", "Sound system" ],
        total_amount: 8500,
        payment_schedule: [
          { amount: 2500, description: "Deposit", due_days_before: 60 },
          { amount: 3000, description: "Second payment", due_days_before: 30 },
          { amount: 3000, description: "Final payment", due_days_before: 7 }
        ],
        rental_dates: (1..3).map { |i| { days_from_now: 45 + (i * 7), hours: 4, space: @main_stage } }
      )

      # Contract 2: Corporate Event
      @corporate_contract = create_contract(
        contractor_name: "TechCorp Industries",
        contractor_email: "events@techcorp.com",
        contractor_phone: "2175552345",
        production_name: "TechCorp Annual Awards Gala",
        services: [ "Lobby rental", "Catering coordination", "A/V setup" ],
        total_amount: 5000,
        payment_schedule: [
          { amount: 2500, description: "Deposit", due_days_before: 30 },
          { amount: 2500, description: "Balance due", due_days_before: 7 }
        ],
        rental_dates: [ { days_from_now: 35, hours: 6, space: @lobby } ]
      )

      # Contract 3: Dance Recital
      @dance_contract = create_contract(
        contractor_name: "Grace Academy of Dance",
        contractor_email: "info@graceacademy.dance",
        contractor_phone: "2175553456",
        production_name: "Spring Dance Recital",
        services: [ "Main Stage rental", "Rehearsal room access", "Lighting" ],
        total_amount: 4200,
        payment_schedule: [
          { amount: 1200, description: "Deposit", due_days_before: 45 },
          { amount: 1500, description: "Rehearsal fees", due_days_before: 14 },
          { amount: 1500, description: "Performance fee", due_days_before: 3 }
        ],
        rental_dates: [
          { days_from_now: 50, hours: 3, space: @rehearsal_a },
          { days_from_now: 51, hours: 3, space: @rehearsal_a },
          { days_from_now: 52, hours: 5, space: @main_stage }
        ]
      )

      # Contract 4: Comedy Night
      @comedy_contract = create_contract(
        contractor_name: "Local Laughs Comedy",
        contractor_email: "bookings@locallaughs.com",
        contractor_phone: "2175554567",
        production_name: "Stand-Up Comedy Night",
        services: [ "Black Box rental", "Sound system", "Lighting" ],
        total_amount: 1800,
        payment_schedule: [
          { amount: 900, description: "Deposit", due_days_before: 14 },
          { amount: 900, description: "Balance", due_days_before: 1 }
        ],
        rental_dates: [ { days_from_now: 21, hours: 3, space: @black_box } ]
      )

      # Contract 5: Wedding Reception
      @wedding_contract = create_contract(
        contractor_name: "Sarah & Michael Smith",
        contractor_email: "smithwedding2026@gmail.com",
        contractor_phone: "2175555678",
        production_name: "Smith Wedding Reception",
        services: [ "Lobby rental", "Setup/teardown", "Parking coordination" ],
        total_amount: 3500,
        payment_schedule: [
          { amount: 1000, description: "Deposit (non-refundable)", due_days_before: 90 },
          { amount: 1250, description: "Second payment", due_days_before: 30 },
          { amount: 1250, description: "Final payment", due_days_before: 7 }
        ],
        rental_dates: [ { days_from_now: 65, hours: 8, space: @lobby } ]
      )

      # Contract 6: Private Concert
      @concert_contract = create_contract(
        contractor_name: "The Jazz Collective",
        contractor_email: "booking@jazzcollective.music",
        contractor_phone: "2175556789",
        production_name: "Evening of Jazz",
        services: [ "Black Box rental", "Piano rental", "Sound system" ],
        total_amount: 2200,
        payment_schedule: [
          { amount: 1100, description: "Deposit", due_days_before: 21 },
          { amount: 1100, description: "Balance", due_days_before: 3 }
        ],
        rental_dates: [ { days_from_now: 28, hours: 4, space: @black_box } ]
      )

      puts "  Created 6 space rental contracts"
    end

    def create_contract(contractor_name:, contractor_email:, contractor_phone:, production_name:, services:, total_amount:, payment_schedule:, rental_dates:)
      # Calculate dates
      start_date = rental_dates.map { |r| r[:days_from_now] }.min.days.from_now.to_date
      end_date = rental_dates.map { |r| r[:days_from_now] }.max.days.from_now.to_date

      contract = Contract.create!(
        organization: @org,
        contractor_name: contractor_name,
        contractor_email: contractor_email,
        contractor_phone: contractor_phone,
        production_name: production_name,
        contract_start_date: start_date,
        contract_end_date: end_date,
        services: services.map { |s| { name: s, description: "" } },
        status: "active",
        activated_at: 2.weeks.ago,
        wizard_step: 5
      )

      # Create payments
      payment_schedule.each do |payment|
        due_date = rental_dates.map { |r| r[:days_from_now] }.min.days.from_now - payment[:due_days_before].days
        ContractPayment.create!(
          contract: contract,
          amount: payment[:amount],
          description: payment[:description],
          due_date: due_date,
          direction: "from",  # Payment from contractor to us
          status: due_date < Time.current ? "paid" : "pending",
          paid_date: due_date < Time.current ? due_date : nil
        )
      end

      # Create third-party production for the rental
      rental_production = Production.create!(
        organization: @org,
        name: production_name,
        production_type: "third_party",
        contact_email: contractor_email
      )

      # Create space rentals and shows
      rental_dates.each do |rental|
        start_time = rental[:days_from_now].days.from_now.change(hour: 18, min: 0)
        end_time = start_time + rental[:hours].hours

        space_rental = SpaceRental.create!(
          contract: contract,
          location: @main_location,
          location_space: rental[:space],
          starts_at: start_time,
          ends_at: end_time,
          confirmed: true
        )

        # Create show linked to rental
        Show.create!(
          production: rental_production,
          date_and_time: start_time,
          event_type: "show",
          location: @main_location,
          location_space: rental[:space],
          space_rental: space_rental,
          casting_enabled: false
        )
      end

      contract
    end

    def create_shows_and_casting
      puts "\nCreating shows and casting..."

      # Sound of Music - Fri/Sat performances for 8 weeks
      create_recurring_shows(@sound_of_music, @main_stage, weeks: 8, days: [ 5, 6 ], hour: 19)

      # Midsummer - Thu/Fri for 6 weeks
      create_recurring_shows(@midsummer, @black_box, weeks: 6, days: [ 4, 5 ], hour: 19, start_offset: 14)

      # Chicago - Sat matinee and evening for 8 weeks
      create_recurring_shows(@chicago, @main_stage, weeks: 8, days: [ 6 ], hour: 14, start_offset: 7)
      create_recurring_shows(@chicago, @main_stage, weeks: 8, days: [ 6 ], hour: 19, start_offset: 7)

      # Improv Workshop - Weekly on Wednesdays
      create_recurring_shows(@improv_workshop, @rehearsal_a, weeks: 12, days: [ 3 ], hour: 19, event_type: "workshop")

      # Spring Showcase - Single show
      show_date = 75.days.from_now.change(hour: 19, min: 0)
      Show.create!(
        production: @spring_showcase,
        date_and_time: show_date,
        event_type: "show",
        location: @main_location,
        location_space: @main_stage,
        casting_enabled: true
      )

      # Cast the shows
      cast_production(@sound_of_music)
      cast_production(@midsummer)
      cast_production(@chicago)
      cast_production(@improv_workshop)

      # Create casting table for Sound of Music + Chicago (shared talent pool)
      create_casting_table

      puts "  Created shows and cast #{@sound_of_music.shows.count + @midsummer.shows.count + @chicago.shows.count + @improv_workshop.shows.count + 1} performances"
    end

    def create_recurring_shows(production, space, weeks:, days:, hour:, start_offset: 0, event_type: "show")
      start_date = (start_offset.days.from_now).beginning_of_week

      weeks.times do |week_num|
        days.each do |day_of_week|
          show_date = start_date + week_num.weeks + day_of_week.days
          show_date = show_date.change(hour: hour, min: 0)

          next if show_date < Time.current  # Don't create past shows

          Show.create!(
            production: production,
            date_and_time: show_date,
            event_type: event_type,
            location: @main_location,
            location_space: space,
            casting_enabled: true
          )
        end
      end
    end

    def cast_production(production)
      talent_pool = production.talent_pools.first
      return unless talent_pool

      pool_members = talent_pool.talent_pool_memberships.map(&:member)
      roles = production.roles.performing

      production.shows.where("date_and_time > ?", Time.current).each do |show|
        roles.each do |role|
          # Assign people to each role
          role.quantity.times do |position|
            person = pool_members.sample
            next unless person

            ShowPersonRoleAssignment.create!(
              show: show,
              role: role,
              assignable: person,
              position: position
            )
          end
        end

        # Mark some shows as casting finalized
        if rand < 0.7  # 70% of shows have finalized casting
          show.update!(casting_finalized_at: 1.day.ago)
        end
      end
    end

    def create_casting_table
      # Create a casting table for Sound of Music and Chicago (they share talent)
      casting_table = CastingTable.create!(
        organization: @org,
        name: "Musical Season Casting",
        status: "draft",
        created_by: @admin_user
      )

      # Add both productions
      CastingTableProduction.create!(casting_table: casting_table, production: @sound_of_music)
      CastingTableProduction.create!(casting_table: casting_table, production: @chicago)

      # Add some shows to the casting table
      [ @sound_of_music, @chicago ].each do |prod|
        prod.shows.where("date_and_time > ?", Time.current).limit(3).each do |show|
          CastingTableEvent.create!(casting_table: casting_table, show: show)
        end
      end
    end

    def create_availability
      puts "\nSetting up availability..."

      # For each production's talent pool, set intelligent availability
      [ @sound_of_music, @midsummer, @chicago, @improv_workshop ].each do |production|
        talent_pool = production.talent_pools.first
        next unless talent_pool

        pool_members = talent_pool.talent_pool_memberships.map(&:member)

        production.shows.where("date_and_time > ?", Time.current).each do |show|
          pool_members.each do |person|
            # Intelligent availability based on patterns
            status = generate_availability_status(person, show)

            ShowAvailability.create!(
              show: show,
              available_entity: person,
              status: status
            )
          end
        end
      end

      puts "  Set availability for talent pool members"
    end

    def generate_availability_status(person, show)
      # Create realistic patterns:
      # - Most people are available (60%)
      # - Some are maybes (25%)
      # - Some are unavailable (15%)
      # - Weekend shows have higher availability
      # - People tend to be consistent (same person likely to have similar patterns)

      person_seed = person.id % 10
      day_of_week = show.date_and_time.wday

      # Weekend boost
      weekend_boost = [ 0, 6 ].include?(day_of_week) ? 0.1 : 0

      # Person tendency (some people are more available than others)
      person_tendency = person_seed < 7 ? 0.1 : -0.1

      base_available = 0.6 + weekend_boost + person_tendency

      roll = rand

      if roll < base_available
        0  # Yes
      elsif roll < base_available + 0.25
        2  # Maybe
      else
        1  # No
      end
    end

    def create_open_mic_with_signups
      puts "\nSetting up Open Mic with sign-up forms..."

      # Create weekly Open Mic shows
      12.times do |week_num|
        show_date = week_num.weeks.from_now.beginning_of_week + 4.days  # Fridays
        show_date = show_date.change(hour: 20, min: 0)

        next if show_date < Time.current

        Show.create!(
          production: @open_mic,
          date_and_time: show_date,
          event_type: "show",
          location: @main_location,
          location_space: @black_box,
          casting_enabled: true,
          signup_based_casting: true
        )
      end

      # Create sign-up form
      sign_up_form = SignUpForm.create!(
        production: @open_mic,
        name: "Open Mic Sign-Up",
        scope: "repeated",
        active: true,
        schedule_mode: "relative",
        opens_days_before: 0,  # Opens day of
        closes_hours_before: 2,  # Closes 2 hours before
        slot_count: 12,
        slot_capacity: 1,
        slot_prefix: "Slot",
        slot_selection_mode: "choose_slot",
        allow_edit: true,
        allow_cancel: true,
        cancel_cutoff_hours: 1,
        require_login: false,
        show_registrations: true,
        notify_on_registration: true
      )

      # Create slots
      12.times do |i|
        SignUpSlot.create!(
          sign_up_form: sign_up_form,
          position: i,
          name: "#{i + 1}. Performance Slot",
          capacity: 1
        )
      end

      # Add custom questions
      Question.create!(
        questionable: sign_up_form,
        text: "What will you be performing?",
        question_type: "short_text",
        position: 0,
        required: true
      )

      Question.create!(
        questionable: sign_up_form,
        text: "Do you need any special equipment?",
        question_type: "long_text",
        position: 1,
        required: false
      )

      # Create instances for upcoming shows and add some registrations
      @open_mic.shows.where("date_and_time > ?", Time.current).limit(4).each do |show|
        instance = SignUpFormInstance.create!(
          sign_up_form: sign_up_form,
          show: show,
          opens_at: show.date_and_time.beginning_of_day,
          closes_at: show.date_and_time - 2.hours,
          status: show.date_and_time.beginning_of_day <= Time.current ? "open" : "scheduled"
        )

        # Add some registrations to the first couple instances
        if show.date_and_time < 2.weeks.from_now
          slots = sign_up_form.sign_up_slots.to_a
          num_registrations = rand(4..8)

          @created_people.sample(num_registrations).each_with_index do |person, idx|
            break if idx >= slots.length

            SignUpRegistration.create!(
              sign_up_form_instance: instance,
              sign_up_slot: slots[idx],
              person: person,
              status: "confirmed",
              position: idx
            )
          end
        end
      end

      puts "  Created Open Mic with #{sign_up_form.sign_up_slots.count} slots"
    end

    def create_audition_cycle
      puts "\nSetting up audition cycle for Spring Showcase..."

      cycle = AuditionCycle.create!(
        production: @spring_showcase,
        active: true,
        opens_at: 1.week.ago,
        closes_at: 3.weeks.from_now,
        allow_video_submissions: true,
        allow_in_person_auditions: true,
        voting_enabled: true,
        audition_voting_enabled: true,
        notify_on_submission: true,
        form_reviewed: true
      )

      # Add audition form questions
      Question.create!(
        questionable: cycle,
        text: "What piece(s) will you be performing?",
        question_type: "long_text",
        position: 0,
        required: true
      )

      Question.create!(
        questionable: cycle,
        text: "Do you have any conflicts during the performance dates?",
        question_type: "long_text",
        position: 1,
        required: true
      )

      Question.create!(
        questionable: cycle,
        text: "How many years of performance experience do you have?",
        question_type: "short_text",
        position: 2,
        required: false
      )

      # Create audition sessions
      session1 = AuditionSession.create!(
        audition_cycle: cycle,
        location: @main_location,
        start_at: 10.days.from_now.change(hour: 10, min: 0),
        end_at: 10.days.from_now.change(hour: 14, min: 0),
        maximum_auditionees: 20
      )

      session2 = AuditionSession.create!(
        audition_cycle: cycle,
        location: @main_location,
        start_at: 11.days.from_now.change(hour: 18, min: 0),
        end_at: 11.days.from_now.change(hour: 21, min: 0),
        maximum_auditionees: 15
      )

      # Create 10 audition requests
      audition_applicants = @created_people.sample(10)

      audition_applicants.each_with_index do |person, idx|
        request = AuditionRequest.create!(
          audition_cycle: cycle,
          requestable: person,
          status: idx < 3 ? "scheduled" : "submitted",
          video_url: idx % 3 == 0 ? "https://www.youtube.com/watch?v=dQw4w9WgXcQ" : nil
        )

        # Schedule some for in-person auditions
        if idx < 5
          session = idx < 3 ? session1 : session2
          Audition.create!(
            audition_request: request,
            audition_session: session,
            auditionable: person
          )
        end

        # Add votes from reviewers
        if idx < 7
          @manager_users.each do |manager|
            vote_value = [ "yes", "maybe", "no" ].sample

            AuditionRequestVote.create!(
              audition_request: request,
              user: manager,
              vote: vote_value
            )
          end
        end
      end

      # Add reviewers
      @manager_users.each do |manager|
        manager_person = manager.people.first
        next unless manager_person

        AuditionReviewer.create!(
          audition_cycle: cycle,
          person: manager_person
        )
      end

      puts "  Created audition cycle with #{audition_applicants.count} applicants"
    end

    def create_financials_and_payouts
      puts "\nSetting up financials and payouts..."

      # Create payout schemes
      @standard_payout = PayoutScheme.create!(
        organization: @org,
        name: "Standard Equal Split",
        description: "Equal distribution among all performers after expenses",
        is_default: true,
        rules: {
          allocation: [
            { type: "fixed_expense", amount: 100, description: "Venue fee" },
            { type: "percentage", amount: 10, description: "Production costs" }
          ],
          distribution: {
            method: "equal",
            include_roles: [ "performing" ]
          }
        }
      )

      @tips_payout = PayoutScheme.create!(
        organization: @org,
        name: "Tips & Donations",
        description: "For tip-based shows like Open Mic",
        rules: {
          allocation: [],
          distribution: {
            method: "equal",
            include_roles: [ "performing" ]
          }
        }
      )

      # Create production-level payout scheme for Sound of Music
      @som_payout = PayoutScheme.create!(
        production: @sound_of_music,
        name: "Sound of Music Payout",
        description: "Per-ticket split with guaranteed minimum",
        rules: {
          allocation: [
            { type: "fixed_expense", amount: 500, description: "Orchestra" },
            { type: "fixed_expense", amount: 200, description: "Costumes & Props" }
          ],
          distribution: {
            method: "per_ticket_guaranteed",
            per_ticket_amount: 2.50,
            minimum_guarantee: 50,
            include_roles: [ "performing" ]
          }
        }
      )

      # Add financials to past shows and some upcoming
      [ @sound_of_music, @midsummer, @chicago ].each do |production|
        scheme = production == @sound_of_music ? @som_payout : @standard_payout

        production.shows.where("date_and_time < ?", Time.current).each do |show|
          create_show_financials(show, scheme)
        end

        # Add financials to a few upcoming shows too
        production.shows.where("date_and_time > ?", Time.current).limit(2).each do |show|
          create_show_financials(show, scheme, past: false)
        end
      end

      # Create advances for some performers
      @created_people.sample(5).each do |person|
        PersonAdvance.create!(
          person: person,
          production: @sound_of_music,
          original_amount: [ 100, 150, 200, 250 ].sample,
          remaining_balance: [ 0, 50, 100 ].sample,
          status: "partial",
          issued_at: 2.weeks.ago,
          issued_by: @admin_user,
          paid_at: 2.weeks.ago,
          paid_by: @admin_user,
          payment_method: "check",
          notes: "Advance for costume purchase"
        )
      end

      puts "  Created payout schemes and financials"
    end

    def create_show_financials(show, payout_scheme, past: true)
      # Create realistic financials
      ticket_count = past ? rand(80..250) : nil
      ticket_price = 25
      ticket_revenue = past ? ticket_count * ticket_price : nil

      financials = ShowFinancials.create!(
        show: show,
        revenue_type: "ticket_sales",
        ticket_revenue: ticket_revenue,
        ticket_count: ticket_count,
        ticket_fees: past ? rand(50..150) : nil,
        expenses: past ? rand(200..500) : nil,
        data_confirmed: past
      )

      # Create payout for past shows
      if past && ticket_revenue
        payout = ShowPayout.create!(
          show: show,
          payout_scheme: payout_scheme,
          status: rand < 0.7 ? "paid" : "awaiting_payout",
          calculated_at: 1.day.ago
        )

        # Create line items for each cast member
        show.show_person_role_assignments.joins(:role).where(roles: { category: "performing" }).each do |assignment|
          next unless assignment.assignable.is_a?(Person)

          person = assignment.assignable
          amount = rand(25..100)

          ShowPayoutLineItem.create!(
            show_payout: payout,
            payee: person,
            amount: amount,
            shares: 1,
            payment_method: person.preferred_payment_method || [ "venmo", "cash", "check" ].sample,
            paid_at: payout.status == "paid" ? 1.day.ago : nil
          )
        end

        # Update total
        payout.update!(total_payout: payout.line_items.sum(:amount))
      end
    end

    def generate_phone_number
      # Generate realistic US phone numbers
      area_codes = [ "217", "312", "773", "630", "847", "708" ]
      "#{area_codes.sample}#{rand(100..999)}#{rand(1000..9999)}"
    end

    def generate_performer_bio(performer)
      bios = [
        "#{performer[:first]} has been performing for over #{rand(3..15)} years and is thrilled to be part of the Starlight Community Theater family.",
        "A graduate of the local performing arts program, #{performer[:first]} specializes in musical theater and contemporary drama.",
        "#{performer[:first]} discovered a love for theater at age #{rand(8..16)} and has been on stage ever since.",
        "When not performing, #{performer[:first]} teaches acting workshops and mentors young performers.",
        "#{performer[:first]} brings #{rand(5..20)} years of experience to every role, with a background in both classical and modern theater.",
        "Originally from the Chicago area, #{performer[:first]} has performed in over #{rand(10..50)} productions across the Midwest."
      ]
      bios.sample
    end

    def print_summary
      puts "\n" + "=" * 60
      puts "DEMO DATA SEEDING COMPLETE"
      puts "=" * 60
      puts "\nOrganization: #{@org.name}"
      puts "\nUsers created: #{@created_users.count}"
      puts "  Admin: demo@#{DEMO_EMAIL_DOMAIN}"
      puts "  Password: #{DEMO_PASSWORD}"
      puts "\nPeople/Profiles: #{@created_people.count}"
      puts "Productions: #{@org.productions.type_in_house.count} in-house, #{@org.productions.type_third_party.count} third-party"
      puts "Contracts: #{@org.contracts.count}"
      puts "Shows: #{Show.joins(:production).where(productions: { organization_id: @org.id }).count}"
      puts "Talent Pool Members: #{TalentPoolMembership.joins(talent_pool: :production).where(productions: { organization_id: @org.id }).count}"
      puts "\nSign-up Forms: #{SignUpForm.joins(:production).where(productions: { organization_id: @org.id }).count}"
      puts "Audition Cycles: #{AuditionCycle.joins(:production).where(productions: { organization_id: @org.id }).count}"
      puts "\nPayout Schemes: #{@org.payout_schemes.count + PayoutScheme.joins(:production).where(productions: { organization_id: @org.id }).count}"
      puts "Show Payouts: #{ShowPayout.joins(show: :production).where(productions: { organization_id: @org.id }).count}"
      puts "\n" + "=" * 60
    end
  end
end
