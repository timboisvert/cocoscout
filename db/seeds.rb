
# Create an initial user if one doesn't already exist
u = User.find_or_create_by(email_address: 'boisvert@gmail.com') do |user|
  user.password = 'password'
end
puts "Tim User created or found."

# Create a Person for Tim Boisvert
tim = Person.find_or_create_by(email: 'boisvert@gmail.com') do |person|
  person.name = 'Tim Boisvert'
  person.pronouns = 'he/him'
  person.socials = 'Instagram: @timboisvert'
end
puts "Tim Boisvert Person created or found."

pc = ProductionCompany.find_or_create_by(name: 'CocoRunsEverything')
puts "CocoRunsEverything created or found."

p = pc.productions.find_or_create_by(name: 'Comedy Pageant', production_company: pc)
puts "Comedy Pageant created or found."

cta = p.call_to_auditions.find_or_create_by(production: p) do |call|
  call.open_at = 1.week.ago
  call.close_at = 2.weeks.from_now
  call.token = SecureRandom.alphanumeric(8).upcase
  call.header_text = "Header text goes here"
  call.success_text = "Success text goes here"
end
puts "Call to Audition created or found."

# Delete the old 50 users
Person.where("email LIKE ?", "%example.com").destroy_all
puts "Old example.com people deleted."

# Make 50 people and have them apply to the call to audition
50.times do |i|
  person = Person.find_or_create_by(email: "person#{i}@example.com") do |p|
    p.name = "Person #{i}"
    p.pronouns = [ 'he/him', 'she/her', 'they/them' ].sample
    p.socials = "Instagram: @person#{i}"
    p.resume.attach(io: StringIO.new(tim.resume.download),
                   filename: tim.resume.filename,
                   content_type: tim.resume.content_type)
    p.headshot.attach(io: StringIO.new(tim.headshot.download),
                     filename: tim.headshot.filename,
                     content_type: tim.headshot.content_type)
  end
  puts "#{person.name} created or found."

  # Have the person apply to the call to audition
  cta.audition_requests.find_or_create_by(person: person) do |request|
    cta.questions.each do |question|
      answer = request.answers.build(question: question)
      if question.question_type == 'text'
        answer.value = SecureRandom.alphanumeric(20)
      elsif question.question_type == 'yesno'
        answer.value = [ "yes", "no" ].sample
      elsif question.question_type == 'multiple-multiple'
        random_text = SecureRandom.alphanumeric(10)
        answer.value = { random_text => random_text }
      elsif question.question_type == 'multiple-single'
        answer.value = SecureRandom.alphanumeric(10)
      end
    end
  end
  puts "Audition request for Person #{i} created or found."
end

# Show each cast member's assigned dates
# pc = ProductionCompany.find_or_create_by(name: 'CocoRunsEverything')
# p = pc.productions.find_or_create_by(name: 'Comedy Pageant', production_company: pc)
# main_cast = p.casts.find_by(name: 'Main Cast')
# people = {}
# main_cast.people.each do |cast_member|
#   people["#{cast_member.name} - #{cast_member.email}"] = []
#   cast_member.show_person_role_assignments.each do |assignment|
#     people["#{cast_member.name} - #{cast_member.email}"] << assignment.show.date_and_time.strftime("%-m/%-d/%Y")
#   end
# end
# people.each do |person, dates|
#   puts "#{person}:"
#   dates.each do |date|
#     puts " - #{date}"
#   end
#   puts ""
# end

# emails = []
# [ "Brody",
#  "Allison",
#  "Em",
#  "Matt Neff",
#  "Nowotny",
#  "Asher",
#  "Rian Sondag",
#  "Tim P",
#  "Conor",
#  "Mancini",
#  "Parra",
#  "Crone",
# "Arias" ].each do |name|
#   person = Person.where("name LIKE ?", "%#{name}%").first
#   emails << person.email
# end

# puts emails.sort.join(", ")
