require "nokogiri"
require "open-uri"

RSPEC_LIB = ["rspec-core", "rspec-expectations", "rspec-mocks", "rspec-rails"]

DOC_CURRENT_VERSION = "http://rspec.info/documentation/3.9"
DOC_NEW_VERSION = "http://0.0.0.0:4567/documentation/3.9"

CLASS_NODES_TO_REMOVE = [
  ".defines",
  ".summary_signature",
  ".signature",
]

ID_NODES_TO_REMOVE = [
  "#Assertions-constant",
]

TEST_ASSERTION_NODE_OFFSET = 2

module Utils
  def get_html(base_url:, page_link:)
    puts ">> Get html for: #{base_url}/#{page_link}"
    Nokogiri::HTML(URI.open("#{base_url}/#{page_link}"))
  end
end

class String
  def to_filename
    "export/#{tr("/", "-")}"
  end
end

class RSpecYardDiffer
  include Utils

  def page_list
    RSPEC_LIB.each_with_object({}) do |lib, list|
      links = get_html(base_url: DOC_CURRENT_VERSION, page_link: "#{lib}/_index.html")
              .css("table a[href]")
              .map { |element| element["href"] }
              .compact
      list["#{lib}"] = links
    end
  end

  def run
    page_list.each do |lib, links|
      links.each { |link| DiffPage.new("#{lib}/#{link}").generate_diff }
    end
  end
end

class DiffPage
  include Utils

  def initialize(page_link)
    @page_link = page_link
  end

  def remove_noise_and_extract_text(html)
    html = remove_assertions_block(html)
    html = remove_selected_class_and_id_div(html)
    html = remove_collapse_expand_buttons(html)

    text = []
    html.at_css("div#content").traverse do |node|
      if skip_new_yard_object_link?(node)
        next
      end
      # puts ">>>>>>> node: #{node.inspect}\n >>>>>> Adding: \n#{node.text} \n _______________________________\n\n" if node.text == "ViewExampleGroup"
      text << node.text
    end
    text.join("")
  end

  def remove_assertions_block(html)
    assertions_constant_node = nil

    return html unless html.css(".constants").first

    html.css(".constants").first.children.each { |node| assertions_constant_node = node if node.attr("id") == "Assertions-constant" }
    assertions_constant_node_id = html.css(".constants").first.children.index(assertions_constant_node)

    return html unless assertions_constant_node_id

    assertion_node = html.css(".constants").first.children[assertions_constant_node_id + 2]
    logger(assertion_node)
    assertion_node.remove
    html
  end

  def remove_selected_class_and_id_div(html)
    (ID_NODES_TO_REMOVE + CLASS_NODES_TO_REMOVE).each do |class_or_id_to_remove|
      html.css(class_or_id_to_remove.to_s).each do |node_to_remove|
        logger(node_to_remove)
        node_to_remove.remove
      end
    end
    html
  end

  def remove_collapse_expand_buttons(html)
    [".constants_summary_toggle", ".summary_toggle"].each do |class_to_remove|
      html.css(class_to_remove.to_s).each do |node_to_remove|
        parent = node_to_remove.parent
        logger(parent)
        parent.remove
      end
    end
    html
  end

  def skip_new_yard_object_link?(node)
    node.attr("class") == "object_link" || node.parent.attr("class") == "object_link"
  end

  def logger(node)
    puts <<-NOTICE
     Removing:
       node.name: #{node.name}
       class: #{AttrDecorator.new(node.attr("class"))}
       id: #{AttrDecorator.new(node.attr("id"))}
       text:⤵️ \n--------------\n#{node.text}\n--------------
    NOTICE
  end

  class AttrDecorator
    def initialize(attribute)
      @attribute = attribute
    end

    def to_s
      @attribute.nil? ? "✖️" : @attribute
    end
  end

  def generate_diff
    current_web_page_file_name = page_link.to_filename + ".current"
    new_web_page_file_name = page_link.to_filename + ".new"

    File.write(
      current_web_page_file_name,
      remove_noise_and_extract_text(get_html(base_url: DOC_CURRENT_VERSION, page_link: page_link))
    )

    File.write(
      new_web_page_file_name,
      remove_noise_and_extract_text(get_html(base_url: DOC_NEW_VERSION, page_link: page_link))
    )

    system(
      <<~SHELL
        git diff \
          --color \
          --no-index \
          --ignore-all-space \
          --ignore-blank-lines \
          --minimal \
          #{current_web_page_file_name} #{new_web_page_file_name} > #{page_link.to_filename}.diff
      SHELL
    )
    puts ">> Diff done: #{page_link.to_filename}.diff"
    system(`cat #{page_link.to_filename}.diff`)
  end

  private

  attr_reader :page_link
end

RSpecYardDiffer.new.run
