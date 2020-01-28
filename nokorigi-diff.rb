require "nokogiri"
require "open-uri"
require "io/console/size"

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
  VerboseMode = {}
  WIDTH = IO.console_size[1]

  def get_html(base_url:, page_link:)
    puts "🧪 Get html for: #{base_url}/#{page_link}"
    Nokogiri::HTML(URI.open("#{base_url}/#{page_link}"))
  end

  if ARGV.any?
    require 'optparse'
    OptionParser.new do |opts|
      opts.on("--diff", "Display git diff") { VerboseMode[:diff] = true }
      opts.on("--removed-content", "Display removed content") { VerboseMode[:removed_content] = true }
      opts.on("--added-text", "Display text extracted") { VerboseMode[:added_text] = true }
      opts.on("--custom-url=url", "Diff only one url. Example: rspec-expectations/RSpec/Matchers/BuiltIn/Exist.html") do |url|
        VerboseMode[:custom_url] = url
      end
    end.parse!
  end
end

class String
  def export_filename
    "export/#{tr("/", "-")}"
  end

  def diff_filename
    "export/diff/#{tr("/", "-")}"
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
    if VerboseMode[:custom_url]
      return DiffPage.new("#{VerboseMode[:custom_url]}").generate_diff
    end

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
    html = add_ending_dot(html)

    text = []
    html.at_css("div#content").traverse do |node|
      if skip_new_yard_object_link?(node)
        next
      end
      if VerboseMode[:added_text]
        puts <<~NOTICE.chomp
          #{"--[ node: ]".ljust(WIDTH, "-")}
          #{node.inspect}
          #{"_" * WIDTH}
          #{"--[ text: ]".ljust(WIDTH, "-")}
          #{node.text}
          #{"_" * WIDTH}
          \n
        NOTICE
      end
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

  def add_ending_dot(html)
    html.css(".discussion p").map do |element|
      if element.content.strip[-1] != "."
        element.content = element.content + "."
      end
    end
    html
  end

  def skip_new_yard_object_link?(node)
    node.attr("class") == "object_link" || node.parent.attr("class") == "object_link"
  end

  def logger(node)
    return unless VerboseMode[:removed_content]
    puts <<~NOTICE.chomp
      #{"--[ Removing: node.name: #{node.name}, class: #{AttrDecorator.new(node.attr("class"))}, id: #{AttrDecorator.new(node.attr("id"))} ]".ljust(WIDTH, "-")}
      text:⤵️

      #{node.text}

      #{"_" * WIDTH}
    NOTICE
  end

  class AttrDecorator
    def initialize(attribute)
      @attribute = attribute
    end

    def to_s
      @attribute.nil? ? "NULL" : @attribute
    end
  end

  def generate_diff
    current_web_page_file_name = page_link.export_filename + ".current"
    new_web_page_file_name = page_link.export_filename + ".new"
    diff_filename = page_link.diff_filename

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
          #{current_web_page_file_name} #{new_web_page_file_name} > #{diff_filename}.diff
      SHELL
    )
    puts "🏆 Diff done: #{diff_filename}.diff\n"
    system("cat #{diff_filename}.diff") if VerboseMode[:diff]
    puts
  end

  private

  attr_reader :page_link
end

RSpecYardDiffer.new.run
