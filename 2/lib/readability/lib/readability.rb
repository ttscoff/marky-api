require "rubygems"
require "nokogiri"
require "guess_html_encoding"

module Readability
  class Document
    DEFAULT_OPTIONS = {
      retry_length: 250,
      min_text_length: 25,
      remove_unlikely_candidates: true,
      weight_classes: true,
      clean_conditionally: true,
      remove_empty_nodes: true,
      min_image_width: 130,
      min_image_height: 80,
      ignore_image_format: [],
      blacklist: nil,
      whitelist: nil,
      likely_siblings: ["p", "div"],
      ignore_redundant_nesting: true,
      attributes: %w[src href],
      elements_to_score: %w[p td pre div article],
      protected_elements: %w[iframe img object],
    }

    REGEXES = {
      unlikelyCandidatesRe: /share|rate|rating|combx|comment|community|disqus|extra|foot|header|menu|remark|rss|shoutbox|sidebar|sponsor|ad-break|agegate|pagination|pager|popup/i,
      okMaybeItsACandidateRe: /and|article|body|column|main|shadow/i,
      positiveRe: /(?<!in-)article|body|content|entry|hentry|main|page|pagination|post|text|blog|story/i,
      negativeRe: /anchor|combx|comment|com-|contact|fairness|foot|footer|footnote|masthead|media|outbrain|promo|related|scroll|shoutbox|sidebar|social|fb|facebook|email|flipboard|whatsapp|twitter|linkedin|reddit|sponsor|share|rate|rating|shopping|tags|tool|widget|newsletter-signup|in-article|recirc/i,
      divToPElementsRe: /<(a|blockquote|dl|div|img|ol|p|pre|table|ul)/i,
      replaceBrsRe: /(<br[^>]*>[ \n\r\t]*){2,}/i,
      replaceFontsRe: %r{<(/?)font[^>]*>}i,
      trimRe: /^\s+|\s+$/,
      normalizeRe: /\s{2,}/,
      killBreaksRe: %r{(<br\s*/?>(\s|&nbsp;?)*){1,}},
      videoRe: %r{http://(www\.)?(youtube|vimeo)\.com}i,
    }

    attr_accessor :options, :html, :best_candidate, :candidates, :best_candidate_has_image

    def initialize(input, options = {})
      debug("Readability::Document#initialize")
      @options = DEFAULT_OPTIONS.merge(options)
      @input = input

      if RUBY_VERSION =~ /^(1\.9|2)/ && !@options[:encoding]
        @input = GuessHtmlEncoding.encode(@input, @options[:html_headers]) unless @options[:do_not_guess_encoding]
        @options[:encoding] = @input.encoding.to_s
      end

      @input = @input.gsub(REGEXES[:replaceBrsRe], "</p><p>").gsub(REGEXES[:replaceFontsRe], '<\1span>')
      @remove_unlikely_candidates = @options[:remove_unlikely_candidates]
      @weight_classes = @options[:weight_classes]
      @clean_conditionally = !!@options[:clean_conditionally]
      @best_candidate_has_image = true
      make_html
      handle_exclusions!(@options[:whitelist], @options[:blacklist])
    end

    def prepare_candidates
      @html.css("script, style").each { |i| i.remove }
      remove_unlikely_candidates! if @remove_unlikely_candidates
      transform_misused_divs_into_paragraphs!

      @candidates = score_paragraphs(options[:min_text_length])
      @best_candidate = select_best_candidate(@candidates)
    end

    def handle_exclusions!(whitelist, blacklist)
      return unless whitelist || blacklist

      if blacklist
        elems = @html.css(blacklist)
        if elems
          elems.each do |e|
            e.remove
          end
        end
      end

      if whitelist
        elems = @html.css(whitelist).to_s

        if body = @html.at_css("body")
          body.inner_html = elems
        end
      end

      @input = @html.to_s
    end

    def make_html(whitelist = nil, blacklist = nil)
      @html = Nokogiri::HTML(@input, nil, @options[:encoding])
      # In case document has no body, such as from empty string or redirect
      @html = Nokogiri::HTML("<body />", nil, @options[:encoding]) if @html.css("body").length == 0

      # Remove html comment tags
      @html.xpath("//comment()").each { |i| i.remove }
    end

    def images(content = nil, reload = false)
      begin
        require "fastimage"
      rescue LoadError
        raise "Please install fastimage in order to use the #images feature."
      end

      @best_candidate_has_image = false if reload

      prepare_candidates
      list_images = []
      tested_images = []
      content = @best_candidate[:elem] unless reload

      return list_images if content.nil?

      elements = content.css("img").map(&:attributes)

      elements.each do |element|
        next unless element["src"]

        url = element["src"].value
        height = element["height"].nil? ? 0 : element["height"].value.to_i
        width = element["width"].nil? ? 0 : element["width"].value.to_i

        if url =~ %r{\Ahttps?://}i && (height.zero? || width.zero?)
          image = get_image_size(url)
          next unless image
        else
          image = { width: width, height: height }
        end

        image[:format] = File.extname(url).gsub(".", "")

        if tested_images.include?(url)
          debug("Image was tested: #{url}")
          next
        end

        tested_images.push(url)
        if image_meets_criteria?(image)
          list_images << url
        else
          debug("Image discarded: #{url} - height: #{image[:height]} - width: #{image[:width]} - format: #{image[:format]}")
        end
      end

      (list_images.empty? and content != @html) ? images(@html, true) : list_images
    end

    def images_with_fqdn_uris!(source_uri)
      images_with_fqdn_uris(@html, source_uri)
    end

    def images_with_fqdn_uris(document = @html.dup, source_uri)
      uri = URI.parse(source_uri)
      host = uri.host
      scheme = uri.scheme
      port = uri.port # defaults to 80

      base = "#{scheme}://#{host}:#{port}/"

      images = []
      document.css("img").each do |elem|
        elem["src"] = URI.join(base, elem["src"]).to_s if URI.parse(elem["src"]).host.nil?
        images << elem["src"].to_s
      rescue URI::InvalidURIError => e
        elem.remove
      end

      images(document, true)
    end

    def get_image_size(url)
      w, h = FastImage.size(url)
      raise "Couldn't get size." if w.nil? || h.nil?

      { width: w, height: h }
    rescue StandardError => e
      debug("Image error: #{e}")
      nil
    end

    def image_meets_criteria?(image)
      return false if options[:ignore_image_format].include?(image[:format].downcase)

      image[:width] >= (options[:min_image_width] || 0) && image[:height] >= (options[:min_image_height] || 0)
    end

    def title
      title = @html.css("title").first
      title ? title.text : nil
    end

    # Look through the @html document looking for the author
    # Precedence Information here on the wiki: (TODO attach wiki URL if it is accepted)
    # Returns nil if no author is detected
    def author
      # Let's grab this author:
      # <meta name="dc.creator" content="Finch - http://www.getfinch.com" />
      author_elements = @html.xpath('//meta[@name = "dc.creator"]')
      unless author_elements.empty?
        author_elements.each do |element|
          return element["content"].strip if element["content"]
        end
      end

      # Now let's try to grab this
      # <span class="byline author vcard"><span>By</span><cite class="fn">Austin Fonacier</cite></span>
      # <div class="author">By</div><div class="author vcard"><a class="url fn" href="http://austinlivesinyoapp.com/">Austin Fonacier</a></div>
      author_elements = @html.xpath('//*[contains(@class, "vcard")]//*[contains(@class, "fn")]')
      unless author_elements.empty?
        author_elements.each do |element|
          return element.inner_html.strip if element.inner_html
        end
      end

      # Now let's try to grab this
      # <a rel="author" href="http://dbanksdesign.com">Danny Banks (rel)</a>
      # TODO: strip out the (rel)?
      author_elements = @html.xpath('//a[@rel = "author"]')
      unless author_elements.empty?
        author_elements.each do |element|
          return element.inner_html.strip if element.inner_html
        end
      end

      author_elements = @html.xpath('//*[@id = "author"]')
      return if author_elements.empty?

      author_elements.each do |element|
        return element.inner_html.strip if element.inner_html
      end
    end

    def content(remove_unlikely_candidates = :default)
      @remove_unlikely_candidates = false if remove_unlikely_candidates == false

      prepare_candidates
      article = get_article(@candidates, @best_candidate)

      cleaned_article = sanitize(article, @candidates, options)

      if article.text.strip.length < options[:retry_length]
        if @remove_unlikely_candidates
          @remove_unlikely_candidates = false
        elsif @weight_classes
          @weight_classes = false
        elsif @clean_conditionally
          @clean_conditionally = false
        else
          # nothing we can do
          return cleaned_article
        end

        make_html
        content
      else
        cleaned_article
      end
    end

    def get_article(candidates, best_candidate)
      # Now that we have the top candidate, look through its siblings for content that might also be related.
      # Things like preambles, content split by ads that we removed, etc.

      sibling_score_threshold = [10, best_candidate[:content_score] * 0.2].max
      downcased_likely_siblings = options[:likely_siblings].map(&:downcase)
      output = Nokogiri::XML::Node.new("div", @html)

      # If the best candidate is the only element in its parent then we will never find any siblings. Therefore,
      # find the closest ancestor that has siblings (if :ignore_redundant_nesting is true). This improves the
      # related content detection, but could lead to false positives. Not supported in arc90's readability.
      node = if options[:ignore_redundant_nesting]
          closest_node_with_siblings(best_candidate[:elem])
        else
          best_candidate[:elem] # This is the default behaviour for consistency with arc90's readability.
        end

      node.parent.children.each do |sibling|
        append = false
        append = true if sibling == node
        append = true if candidates[sibling] && candidates[sibling][:content_score] >= sibling_score_threshold

        if downcased_likely_siblings.include?(sibling.name.downcase)
          link_density = get_link_density(sibling)
          node_content = sibling.inner_html.strip
          node_length = node_content.length

          append = if node_length > 80 && link_density < 0.25
              true
            elsif node_length < 80 && link_density == 0 && node_content =~ /\.( |$)/
              true
            end
        end

        next unless append

        sibling_dup = sibling.dup # otherwise the state of the document in processing will change, thus creating side effects
        sibling_dup.name = "div" unless %w[div p].include?(sibling.name.downcase)
        output << sibling_dup
      end

      output
    end

    def closest_node_with_siblings(element)
      node = element

      until node.node_name == "body"
        siblings = node.parent.children
        non_empty = siblings.reject { |sibling| sibling.text? && sibling.text.strip.empty? }

        # return node if non_empty.size > 1

        # Experimenting with a more lenient approach
        if non_empty.size > 1
          test = node.parent
          non_empty_parent = test.children.reject { |child| child.text? && child.text.strip.empty? }
          if non_empty_parent.size > 1
            return test
          else
            return node
          end
        end
        # end experiment

        node = node.parent
      end

      node
    end

    def select_best_candidate(candidates)
      sorted_candidates = candidates.values.sort { |a, b| b[:content_score] <=> a[:content_score] }

      debug("Top 5 candidates:")
      sorted_candidates[0...5].each do |candidate|
        debug("Candidate #{candidate[:elem].name}##{candidate[:elem][:id]}.#{candidate[:elem][:class]} with score #{candidate[:content_score]}")
      end

      best_candidate = sorted_candidates.first || { elem: @html.css("body").first, content_score: 0 }
      debug("Best candidate #{best_candidate[:elem].name}##{best_candidate[:elem][:id]}.#{best_candidate[:elem][:class]} with score #{best_candidate[:content_score]}")

      best_candidate
    end

    def get_link_density(elem)
      link_length = elem.css("a").map(&:text).join("").length
      text_length = elem.text.length
      link_length / text_length.to_f
    end

    def score_paragraphs(min_text_length)
      candidates = {}
      @html.css(options[:elements_to_score].join(",")).each do |elem|
        parent_node = elem.parent
        grand_parent_node = parent_node.respond_to?(:parent) ? parent_node.parent : nil
        inner_text = elem.text

        # If this paragraph is less than 25 characters, don't even count it.
        next if inner_text.length < min_text_length

        candidates[parent_node] ||= score_node(parent_node)
        candidates[grand_parent_node] ||= score_node(grand_parent_node) if grand_parent_node

        content_score = 1
        content_score += inner_text.split(",").length
        content_score += [(inner_text.length / 100).to_i, 3].min

        candidates[parent_node][:content_score] += content_score
        candidates[grand_parent_node][:content_score] += content_score / 2.0 if grand_parent_node
      end

      # Scale the final candidates score based on link density. Good content should have a
      # relatively small link density (5% or less) and be mostly unaffected by this operation.
      candidates.each do |elem, candidate|
        candidate[:content_score] = candidate[:content_score] * (1 - get_link_density(elem))
      end

      candidates
    end

    def class_weight(e)
      weight = 0
      return weight unless @weight_classes

      if e[:class] && e[:class] != ""
        weight -= 25 if e[:class] =~ REGEXES[:negativeRe]
        weight += 25 if e[:class] =~ REGEXES[:positiveRe]
      end

      if e[:id] && e[:id] != ""
        weight -= 25 if e[:id] =~ REGEXES[:negativeRe]
        weight += 25 if e[:id] =~ REGEXES[:positiveRe]
      end

      weight
    end

    ELEMENT_SCORES = {
      "div" => 5,
      "blockquote" => 3,
      "form" => -3,
      "th" => -5,
    }.freeze

    def score_node(elem)
      content_score = class_weight(elem)
      content_score += ELEMENT_SCORES.fetch(elem.name.downcase, 0)
      { content_score: content_score, elem: elem }
    end

    def debug(str)
      Marky.log.debug(str)
    end

    def remove_unlikely_candidates!
      @html.css("*").each do |elem|
        str = "#{elem[:class]}#{elem[:id]}"
        if str =~ REGEXES[:unlikelyCandidatesRe] && str !~ REGEXES[:okMaybeItsACandidateRe] && (elem.name.downcase != "html") && (elem.name.downcase != "body")
          debug("Removing unlikely candidate - #{str}")
          elem.remove
        end
      end
    end

    def has_protected_elements?(elem)
      return false if elem.nil?

      @options[:protected_elements].each do |tag|
        return true if elem.css(tag).length > 0
      end
    end

    def transform_misused_divs_into_paragraphs!
      @html.css("*").each do |elem|
        if elem.name.downcase == "div"
          # transform <div>s that do not contain other block elements into <p>s
          if elem.inner_html !~ REGEXES[:divToPElementsRe]
            debug("Altering div(##{elem[:id]}.#{elem[:class]}) to p")
            elem.name = "p"
          end
        else
          # wrap text nodes in p tags
          #          elem.children.each do |child|
          #            if child.text?
          #              debug("wrapping text node with a p")
          #              child.swap("<p>#{child.text}</p>")
          #            end
          #          end
        end
      end
    end

    def sanitize(node, candidates, options = {})
      # node.css('h1, h2, h3, h4, h5, h6').each do |header|
      #   header.remove if class_weight(header) < 0 || get_link_density(header) > 0.33
      # end
      # Just remove all SVGs for now
      node.css("svg").each do |svg|
        if svg.parent.name.downcase == "a"
          svg.parent.remove
        else
          svg.remove
        end
      end

      # Remove all empty <a> tags
      node.css("a").each do |a|
        a.remove if a.text.strip.empty? && a.css("img").empty?
      end

      # Convert misused <a> tags into <p> tags
      node.css("a").each do |a|
        a.name = "p" if a.text.strip.length > 60
      end

      node.css("div, p, span, a, aside").each do |elem|
        elem.remove if class_weight(elem) < 0
      end

      node.css("form, object, embed").each do |elem|
        elem.remove
      end

      if @options[:remove_empty_nodes]
        # remove <p> tags that have no text content - this will also remove p tags that contain only images.
        node.css("p").each do |elem|
          elem.remove if elem.content.strip.empty? && !has_protected_elements?(elem)
        end
      end

      # # Conditionally clean <table>s, <ul>s, and <div>s
      # clean_conditionally(node, candidates, 'table, ul, div')

      # # We'll sanitize all elements using a whitelist
      base_whitelist = @options[:tags] || %w[div p]
      all_tags_whitelisted = base_whitelist.include?("*")
      all_attr_whitelisted = @options[:attributes] && @options[:attributes].include?("*")

      # # We'll add whitespace instead of block elements,
      # # so a<br>b will have a nice space between them
      # base_replace_with_whitespace = %w[br hr h1 h2 h3 h4 h5 h6 dl dd ol li ul address blockquote center]

      # # Use a hash for speed (don't want to make a million calls to include?)
      # whitelist = {}
      # base_whitelist.each { |tag| whitelist[tag] = true }
      # replace_with_whitespace = {}
      # base_replace_with_whitespace.each { |tag| replace_with_whitespace[tag] = true }

      ([node] + node.css("*")).each do |el|
        # If element is in whitelist, delete all its attributes
        # if all_tags_whitelisted || whitelist[el.node_name]
        next if all_attr_whitelisted

        next if el.name.downcase == "path" || el.name.downcase == "svg"

        el.attributes.each do |a, x|
          el.delete(a) unless @options[:attributes] && @options[:attributes].include?(a.to_s)
        end

        # Otherwise, replace the element with its contents
        # else
        # # If element is root, replace the node as a text node
        # if el.parent.nil?
        #   node = Nokogiri::XML::Text.new(el.text, el.document)
        #   break
        # else
        #   if replace_with_whitespace[el.node_name]
        #     el.swap(Nokogiri::XML::Text.new(' ' << el.text << ' ', el.document))
        #   else
        #     el.swap(Nokogiri::XML::Text.new(el.text, el.document))
        #   end
        # end
        # end
      end

      s = Nokogiri::XML::Node::SaveOptions
      save_opts = s::NO_DECLARATION | s::NO_EMPTY_TAGS | s::AS_XHTML
      html = node.serialize(save_with: save_opts)

      # Get rid of duplicate whitespace
      html.gsub(/[\r\n\f]+/, "\n")
    end

    def clean_conditionally(node, candidates, selector)
      return unless @clean_conditionally

      node.css(selector).each do |el|
        weight = class_weight(el)
        content_score = candidates[el] ? candidates[el][:content_score] : 0
        name = el.name.downcase
        remove = false
        message = nil

        if weight + content_score < 0
          remove = true
          message = "Conditionally cleaned #{name}##{el[:id]}.#{el[:class]} with weight #{weight} and content score #{content_score} because score + content score was less than zero."
        elsif el.text.count(",") < 10
          counts = %w[p img li a embed input].each_with_object({}) do |kind, m|
            m[kind] = el.css(kind).length
          end
          counts["li"] -= 100

          # For every img under a noscript tag discount one from the count to avoid double counting
          counts["img"] -= el.css("noscript").css("img").length

          content_length = el.text.strip.length # Count the text length excluding any surrounding whitespace
          link_density = get_link_density(el)

          reason = clean_conditionally_reason?(name, counts, content_length, options, weight, link_density)
          if reason
            message = "Conditionally cleaned #{name}##{el[:id]}.#{el[:class]} with weight #{weight} and content score #{content_score} because it has #{reason}."
            remove = true
          end
        end

        if options[:clean_conditionally].respond_to?(:call)
          context = { remove: remove, message: message, weight: weight, content_score: content_score, el: el }
          remove = options[:clean_conditionally].call(context) # Allow the user to override the decision for whether to remove the element.
        end

        if remove
          debug(message || "Conditionally cleaned by user-specified function.")
          el.remove
        end
      end
    end

    def clean_conditionally_reason?(name, counts, content_length, options, weight, link_density)
      if (counts["img"] > counts["p"]) && (counts["img"] > 1)
        "too many images"
      elsif counts["li"] > counts["p"] && name != "ul" && name != "ol"
        "more <li>s than <p>s"
      elsif counts["input"] > (counts["p"] / 3).to_i
        "less than 3x <p>s than <input>s"
      elsif (content_length < options[:min_text_length]) && (counts["img"] != 1)
        "too short a content length without a single image"
      elsif weight < 25 && link_density > 0.2
        "too many links for its weight (#{weight})"
      elsif weight >= 25 && link_density > 0.5
        "too many links for its weight (#{weight})"
      elsif (counts["embed"] == 1 && content_length < 75) || counts["embed"] > 1
        "<embed>s with too short a content length, or too many <embed>s"
      else
        nil
      end
    end
  end
end
