# frozen_string_literal: true

class CastingTableMailer < ApplicationMailer
  def casting_notification(person:, casting_table:, assignments:)
    @person = person
    @casting_table = casting_table
    @assignments = assignments
    @organization = casting_table.organization

    # Group assignments by production for display
    @assignments_by_production = assignments.group_by { |a| a.show.production }

    # Build production names for subject (e.g., "Show A, Show B, and Show C")
    production_names = @assignments_by_production.keys.map(&:name)
    @production_names = format_production_names(production_names)

    # Build shows list HTML grouped by production
    @shows_by_production = build_shows_by_production_html

    # Get the email template
    template = EmailTemplate.find_by(key: "casting_table_notification")

    if template
      subject = template.render_subject(production_names: @production_names)
      @email_body = template.render_body(
        production_names: @production_names,
        shows_by_production: @shows_by_production
      )
    else
      # Fallback if template not found
      subject = "Cast Confirmation: #{@production_names}"
      @email_body = build_fallback_body
    end

    mail(
      to: @person.user&.email_address,
      subject: subject
    )
  end

  private

  def format_production_names(names)
    case names.length
    when 0
      ""
    when 1
      names.first
    when 2
      names.join(" and ")
    else
      "#{names[0..-2].join(', ')}, and #{names.last}"
    end
  end

  def build_shows_by_production_html
    html = ""
    @assignments_by_production.each do |production, prod_assignments|
      html += "<h3>#{production.name}</h3>\n<ul>\n"
      prod_assignments.group_by(&:show).each do |show, show_assignments|
        roles = show_assignments.map { |a| a.role.name }.join(", ")
        html += "<li>#{show.date_and_time.strftime('%A, %B %-d, %Y at %-I:%M %p')} - #{roles}</li>\n"
      end
      html += "</ul>\n"
    end
    html
  end

  def build_fallback_body
    html = "<p>You have been cast for the following shows:</p>\n"
    html += build_shows_by_production_html
    html += "<p>Please let us know if you have any scheduling conflicts or questions.</p>"
    html
  end
end
