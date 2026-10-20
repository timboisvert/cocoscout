# frozen_string_literal: true

# Which app build is asking, from its user agent. V1.1 builds put
# "CocoScout/1.1 (12; nav 2)" ahead of Hotwire Native's own user agent
# (AppConfig on iOS and Android); V1 builds put nothing there.
#
# The navigation generation is what matters, not the version number: Tap to
# Pay builds can carry a higher version (Android's is already 1.2) while still
# drawing V1's navigation. Generation 1 is every V1 install. Generation 2 is
# production mode in the app, the universal Messages and Notifications icons,
# and its own page rules (public/hotwire-native/nav-2). Nothing for
# generation 2 may reach a generation-1 phone.
module NativeAppVersion
  PATTERN = %r{CocoScout/(?<version>[\w.]+) \((?<build>\w+); nav (?<nav>\d+)\)}

  module_function

  # The navigation generation: 1 for a V1 build, nil outside the app.
  def nav(user_agent)
    ua = user_agent.to_s
    return nil unless ua.include?("Turbo Native") || ua.include?("Hotwire Native")

    match = PATTERN.match(ua)
    match ? match[:nav].to_i : 1
  end

  def version(user_agent)
    PATTERN.match(user_agent.to_s)&.[](:version)
  end

  # Production mode and the generation-2 menu: everywhere on the web, and in
  # app builds that draw it.
  def production_mode?(user_agent)
    generation = nav(user_agent)
    generation.nil? || generation >= 2
  end
end
