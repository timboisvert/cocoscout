import { Controller } from "@hotwired/stimulus"

// Handles profile navigation scroll spy and smooth scrolling
export default class extends Controller {
  static targets = ["link", "section"]

  connect() {
    this.updateActiveSection = this.updateActiveSection.bind(this)
    this.handleScroll = this.throttle(this.updateActiveSection, 100)

    window.addEventListener('scroll', this.handleScroll)

    // Update on load
    this.updateActiveSection()

    // Handle hash on page load
    if (window.location.hash) {
      setTimeout(() => this.scrollToHash(window.location.hash), 100)
    }
  }

  disconnect() {
    window.removeEventListener('scroll', this.handleScroll)
  }

  scrollTo(event) {
    event.preventDefault()
    const targetId = event.currentTarget.getAttribute('href')
    this.scrollToHash(targetId)
  }

  scrollToHash(hash) {
    const target = document.querySelector(hash)
    if (target) {
      const headerOffset = 80
      const elementPosition = target.getBoundingClientRect().top
      const offsetPosition = elementPosition + window.pageYOffset - headerOffset

      window.scrollTo({
        top: offsetPosition,
        behavior: 'smooth'
      })
    }
  }

  updateActiveSection() {
    const scrollPos = window.scrollY + 100

    // Find sections
    const sections = this.linkTargets.map(link => {
      const targetId = link.getAttribute('href').substring(1)
      return document.getElementById(targetId)
    }).filter(Boolean)

    // Find current section
    let currentSection = null
    sections.forEach(section => {
      const sectionTop = section.offsetTop
      const sectionBottom = sectionTop + section.offsetHeight

      if (scrollPos >= sectionTop && scrollPos < sectionBottom) {
        currentSection = section
      }
    })

    // Update link styles
    this.linkTargets.forEach(link => {
      const targetId = link.getAttribute('href').substring(1)
      if (currentSection && currentSection.id === targetId) {
        link.classList.add('bg-gray-200', 'text-pink-600')
        link.classList.remove('bg-transparent', 'text-black')
      } else {
        link.classList.remove('bg-gray-200', 'text-pink-600')
        link.classList.add('bg-transparent', 'text-black')
      }
    })
  }

  // Throttle helper to limit scroll event frequency
  throttle(func, wait) {
    let timeout = null
    let previous = 0

    return function () {
      const now = Date.now()
      const remaining = wait - (now - previous)

      if (remaining <= 0 || remaining > wait) {
        if (timeout) {
          clearTimeout(timeout)
          timeout = null
        }
        previous = now
        func()
      } else if (!timeout) {
        timeout = setTimeout(() => {
          previous = Date.now()
          timeout = null
          func()
        }, remaining)
      }
    }
  }
}
