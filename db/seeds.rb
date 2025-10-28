
people = []
Person.where(user_id: nil).each do |person|
  productions = person.casts.includes(:production).map(&:production).uniq
  next if productions.empty?
  people << { name: person.name, email: person.email, casts: productions.map(&:name).join(', ') }
end
people

[ { name: "Carlos Rivera", email: "miamicomedyarts@gmail.com", casts: "Comedy Pageant" },
 { name: "Thom Murray", email: "thomjmurray@gmail.com", casts: "Comedy Pageant" },
 { name: "Declan Parker Rhodes", email: "DeclanParkerRhodes@gmail.com", casts: "Comedy Pageant" },
 { name: "Dan Feltey", email: "dfeltey@gmail.com", casts: "Comedy Pageant" },
 { name: "Colleen Grogan", email: "colleengrogantrack@gmail.com", casts: "Comedy Pageant" },
 { name: "Quinn Hatch", email: "hatchquinn@gmail.com", casts: "Comedy Pageant" },
 { name: "Cassie McGrath", email: "cassiemcgrath3@gmail.com", casts: "Comedy Pageant" },
 { name: "Clay Smith", email: "claytonrsmith2@gmail.com", casts: "Comedy Pageant" },
 { name: "Pasquale-Monk", email: "pasqualemonk@gmail.com", casts: "Comedy Pageant" },
 { name: "Ben House", email: "benjaminhouse.e@gmail.com", casts: "Comedy Pageant" },
 { name: "Janelle Kloth ", email: "janelle.kloth@gmail.com", casts: "Comedy Pageant" },
 { name: "Katie Rae Horn", email: "ktraehorn@gmail.com", casts: "Comedy Pageant" },
 { name: "Zach Masso", email: "massozach@gmail.com", casts: "Comedy Pageant" } ]
