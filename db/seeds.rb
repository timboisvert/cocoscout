
# Associate all people with production company 1 if it's namedCoco Runs Everything"
production_company = ProductionCompany.find_by(id: 1)
if production_company && production_company.name == "Coco Runs Everything"
  Person.find_each do |person|
    unless person.production_companies.include?(production_company)
      person.production_companies << production_company
      putsAdded # {person.name} to #{production_company.name}"
    end
  end
end

people = []
Person.where(user_id: nil).each do |person|
  productions = person.casts.includes(:production).map(&:production).uniq
  next if productions.empty?
  people << person.email
end
puts people
