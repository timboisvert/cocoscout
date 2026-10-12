# frozen_string_literal: true

# A sign-in's device in words, from its user agent, for the Account page's
# list of where you're signed in: "CocoScout app on iPhone", "Safari on Mac".
module DeviceLabel
  module_function

  def from_user_agent(user_agent)
    ua = user_agent.to_s
    device = device_name(ua)
    return "CocoScout app on #{device || 'a phone'}" if ua.match?(/Turbo Native|Hotwire Native|CocoScout\//)

    browser = case ua
    when /Edg\// then "Edge"
    when /Firefox\//, /FxiOS/ then "Firefox"
    when /Chrome\//, /CriOS/ then "Chrome"
    when /Safari\// then "Safari"
    end
    return device || "A browser" unless browser

    device ? "#{browser} on #{device}" : browser
  end

  def device_name(ua)
    case ua
    when /iPad/ then "iPad"
    when /iPhone/ then "iPhone"
    when /Android/ then "Android"
    when /Macintosh|Mac OS X/ then "Mac"
    when /Windows/ then "Windows"
    when /Linux/ then "Linux"
    end
  end
end
