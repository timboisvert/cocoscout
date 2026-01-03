# frozen_string_literal: true

# Associate all people with production company 1 if it's named "Coco Runs Everything"
organization = Organization.find_by(id: 1)
if organization && organization.name == 'Coco Runs Everything'
  Person.find_each do |person|
    unless person.organizations.include?(organization)
      person.organizations << organization
      puts "Added #{person.name} to #{organization.name}"
    end
  end
end

people = []
Person.where(user_id: nil).each do |person|
  productions = person.talent_pools.includes(:production).map(&:production).uniq
  next if productions.empty?

  people << person.email
end
puts people
