# frozen_string_literal: true

module Marky
  class StackOverflow
    def initialize(input = nil)
      @input = input
    end

    ## Shortcut for #new.process
    def self.process(input = nil)
      new(input).process
    end

    def process(input = nil)
      input ||= @input
      return nil if input.nil?

      output = []
      output << '<div readability="100.00">'

      doc = Nokogiri::HTML(input)
      title = doc.css('div#question-header h1').text
      output << "<h1>#{title}</h1>"

      doc.css('div.question').each do |question|
        output << question.css('.post-text, .js-post-body').inner_html
        output << "<p>Asked by #{question.css('td.post-signature.owner .user-info .user-details>a')}</p>"
        question.css('.comment-body').each do |comment|
          output << "<blockquote>#{comment.inner_html}</blockquote>"
        end
      end

      doc.css('div.answer').each do |answer|
        output << '<hr>'

        output << '<p><b>Accepted answer:</b></p>' if answer['class'] =~ /accepted-answer/

        output << answer.css('.post-text, .js-post-body').inner_html
        output << "<p>Answer by #{answer.css('.post-signature .user-info .user-details>a')}</p>"
        answer.css('.comment-body').each do |comment|
          output << "<blockquote>#{comment.inner_html}</blockquote>"
        end
      end
      output << '</div>'
      [output.join("\n"), title]
    end
  end
end
