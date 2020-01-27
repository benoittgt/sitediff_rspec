require 'nokogiri'
require 'open-uri'
require 'erb'

DOC_CURRENT_VERSION = "http://rspec.info/documentation/3.9"
DOC_NEW_VERSION = "http://0.0.0.0:4567/documentation/3.9"

PAGE_LIST = [
  "rspec-rails/RSpec/Rails"
]

CLASS_NODES_TO_REMOVE = [
  ".defines",
  ".summary_signature",
  ".signature"
]

ID_NODES_TO_REMOVE = [
  "#Assertions-constant"
]

TEST_ASSERTION_NODE_OFFSET = 2

def get_html(base_url: , page_link:)
  puts ">> Get html for: #{base_url}/#{page_link}.html"
  Nokogiri::HTML(URI.open("#{base_url}/#{page_link}.html"))
end

def remove_noise_and_extract_text(html)
  text = []
  assertions_constant_node = nil
  html.css(".constants").first.children.each { |node| assertions_constant_node = node if node.attr('id') == 'Assertions-constant' }
  assertions_constant_node_id = html.css(".constants").first.children.index(assertions_constant_node)

  assertion_node = html.css(".constants").first.children[assertions_constant_node_id + 2]
  logger(assertion_node)
  assertion_node.remove

  (ID_NODES_TO_REMOVE + CLASS_NODES_TO_REMOVE).each do |class_or_id_to_remove|
    html.css("#{class_or_id_to_remove}").each do |node_to_remove|
      logger(node_to_remove)
      node_to_remove.remove
    end
  end

  html.at_css("div#content").traverse do |node|
    if node.text =~ /collapse|\+ \(Object\)| ⇒ Object /
      logger(node)
      node.remove
      next
    end
    text << node.text
  end
  text.join('')
end

def logger(node)
  @node = node
  notice = ERB.new("
       Removing node:
         <% if @node.name %>node.name: <%= @node.name %><% end %>
         <% if @node.attr('class') %>class:: <%= @node.attr('class') %><% end %>
         <% if @node.attr('id') %>id:: <%= @node.attr('id') %><% end %>
         text: \n      --------------\n:       <%= @node.text %>\n      --------------
         ")
  puts notice.result
end

class String
  def to_filename
    "export/#{tr("/", "-")}"
  end
end

PAGE_LIST.each do |page_link|
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
       --no-index \
       --ignore-all-space \
       --ignore-blank-lines \
       --minimal \
       #{current_web_page_file_name} #{new_web_page_file_name} > #{page_link.to_filename}.diff
     SHELL
  )
  puts ">> Diff done: #{page_link.to_filename}.diff"
end


