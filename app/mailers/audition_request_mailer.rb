class AuditionRequestMailer < ApplicationMailer
  def new_audition_request(audition_request)
    @audition_request = audition_request
    @call_to_audition = @audition_request.call_to_audition
    @person = @audition_request.person

    # For now, just email Tim and Andie when a new audition request comes in
    mail(to: "cocorunseverything@gmail.com", subject: "New Audition Request for #{@call_to_audition.production.title}: #{@person.name}")
  end
end
