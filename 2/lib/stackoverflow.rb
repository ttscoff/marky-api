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
        owner = question.css('.post-signature.owner .user-info .user-details>a').first
        if owner
          ref = owner.attributes['href'].value
          output << %(<p>Asked by <a href="#{ref}">#{owner.content}</a></p>)
        end
        question.css('.comment-body').each do |comment|
          output << "<blockquote>#{comment.inner_html}</blockquote>"
        end
      end
      accepted_answer = nil
      answers = []
      doc.css('div.answer').each do |answer|
        res = []
        vote_count = answer.css('.js-vote-count').first.content.to_i
        res << '<hr>'

        res << '<h3>Accepted answer:</h3>' if answer['class'] =~ /accepted-answer/

        author = answer.css('.post-signature .user-info .user-details>a').first
        href = author.attributes['href'].value
        res << %(<h5>Answer by <a href="#{href}">#{author.content}</a> <em>[Vote count: #{vote_count}]</em></h5>)
        res << answer.css('.post-text, .js-post-body').inner_html
        answer.css('.comment-body').each do |comment|
          copy = comment.css('.comment-copy').first
          author_div = comment.css('.comment-user').first
          if author_div
            author = %(<cite><a href="#{author_div.attributes['href'].value}">#{author_div.inner_html}</a></cite>)
          else
            author = ''
          end
          res << "<blockquote>#{copy.inner_html}#{author}</blockquote>"
        end

        if answer['class'] =~ /accepted-answer/
          accepted_answer = res.join("\n")
        else
          answers << { count: vote_count, content: res.join("\n") }
        end
      end

      output << accepted_answer if accepted_answer

      answers.sort_by { |e| e[:count] }.reverse.each { |answer| output << answer[:content] }

      output << '</div>'
      [output.join("\n"), title]
    end
  end
end
