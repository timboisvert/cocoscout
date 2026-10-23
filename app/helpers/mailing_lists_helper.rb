# frozen_string_literal: true

# Small shared bits for the mailing list pages (Mailing lists, V1.1).
module MailingListsHelper
  # The standard bordered input (form-input-style).
  FOLLOWER_INPUT = "block w-full px-3 py-2.5 bg-white border border-gray-300 rounded-lg shadow-sm text-sm text-gray-900 " \
                   "placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-pink-500"

  def follower_input_class = FOLLOWER_INPUT

  def follower_count_words(count)
    pluralize(number_with_delimiter(count), "follower")
  end

  def follower_money(cents)
    number_to_currency(cents.to_i / 100.0, precision: (cents.to_i % 100).zero? ? 0 : 2)
  end

  # A list row's second line: where it collects and who can see it.
  def mailing_list_line(list, collects:, shares:)
    return "Every production's checkout · added by hand" if list.main?

    parts = []
    parts << (collects.to_i.positive? ? "Collects from #{pluralize(collects, 'production')}" : "Doesn't collect at checkout")
    parts.join(" · ")
  end

  def follower_status_chip(follower)
    case follower.status
    when "unsubscribed" then [ "Unsubscribed", "bg-amber-50 text-amber-700" ]
    when "bounced" then [ "Bounced", "bg-amber-50 text-amber-700" ]
    when "complained" then [ "Marked as spam", "bg-amber-50 text-amber-700" ]
    end
  end

  def chevron_svg
    tag.svg(class: "w-5 h-5 text-gray-400 flex-shrink-0", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24", "aria-hidden": "true") do
      tag.path("stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M9 5l7 7-7 7")
    end
  end
end
