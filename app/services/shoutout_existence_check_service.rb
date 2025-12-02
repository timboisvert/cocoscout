class ShoutoutExistenceCheckService
  def initialize(shoutee_type, shoutee_id, current_user)
    @shoutee_type = shoutee_type
    @shoutee_id = shoutee_id
    @current_user = current_user
  end

  def call
    return false if @shoutee_type.blank? || @shoutee_id.blank?

    shoutee = find_shoutee
    return false if shoutee.nil?

    check_for_existing_shoutout(shoutee)
  end

  private

  def find_shoutee
    case @shoutee_type
    when "Person"
      Person.find_by(id: @shoutee_id)
    when "Group"
      Group.find_by(id: @shoutee_id)
    end
  end

  def check_for_existing_shoutout(shoutee)
    @current_user.person.given_shoutouts
      .where(shoutee: shoutee)
      .where(id: Shoutout.left_joins(:replacement).where(replacement: { id: nil }).select(:id))
      .exists?
  end
end
