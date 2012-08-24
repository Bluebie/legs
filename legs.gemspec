Gem::Specification.new do |s|
  s.name = "legs"
  s.version = "0.6.4"
  s.date = "2012-08-24"
  s.summary = "Simple fun open networking for newbies and quick hacks"
  s.email = "a@creativepony.com"
  s.homepage = "http://github.com/Bluebie/legs"
  s.description = "Legs is a really simple fun networking library that uses 'json-rpc' formated messages over a tcp connection to really easily built peery or server-clienty sorts of apps, for ruby newbies and hackers to build fun little things."
  s.has_rdoc = false
  s.authors = ["Jenna Fox"]
  s.files = ["README.rdoc", "legs.gemspec", "lib/legs.rb", "examples/echo-server.rb", "examples/chat-server.rb", "examples/shoes-chat-client.rb", "test/test_legs.rb"]
  s.add_dependency("json_pure", ["> 1.1.0"])
end