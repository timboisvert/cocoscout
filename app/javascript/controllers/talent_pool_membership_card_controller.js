import { Controller } from "@hotwired/stimulus"

// Usage: data-controller="talent-pool-membership-card"
export default class extends Controller {
    static targets = ["form", "card"]
    connect() { }

    add(event) {
        event.preventDefault()
        const form = this.formTarget
        const url = form.action
        const method = form.method || 'post'
        const data = new FormData(form)

        fetch(url, {
            method: method.toUpperCase(),
            headers: { 'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml, application/xml;q=0.9,*/*;q=0.8' },
            body: data
        })
            .then(response => {
                if (!response.ok) throw new Error('Network error')
                return response.text()
            })
            .then(html => {
                this.cardTarget.outerHTML = html
            })
            .catch(error => {
                alert('There was an error updating the pool membership.')
            })
    }

    remove(event) {
        event.preventDefault();
        const link = event.currentTarget;
        const url = link.getAttribute('href');
        const personId = link.dataset.personId;
        const talentPoolId = link.dataset.talentPoolId;
        const card = this.cardTarget;
        const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

        fetch(url, {
            method: 'POST',
            headers: {
                'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml, application/xml;q=0.9,*/*;q=0.8',
                'X-CSRF-Token': token,
                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
            },
            body: new URLSearchParams({ person_id: personId, talent_pool_id: talentPoolId })
        })
            .then(response => {
                if (!response.ok) throw new Error('Network error')
                return response.text()
            })
            .then(html => {
                card.outerHTML = html
            })
            .catch(error => {
                alert('There was an error removing from the cast.')
            })
    }




}
