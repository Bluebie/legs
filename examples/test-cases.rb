require '../legs.rb'

Legs.log = false

# a simple server to test with
Legs.start(6425) do
  def echo(text)
    return text
  end
  
  def count
    caller.meta[:counter] ||= 0
    caller.meta[:counter] += 1
  end
  
  def error
    raise StandardError.new("This is a fake error")
  end
  
  def test_notify
    puts "Success"
  end
end

## connects and tests a bunch of things
puts "Testing syncronous method_missing style echo"
i = Legs.new('localhost',6425)
puts i.echo('Hello World') == 'Hello World' ?"Success":"Failure"

puts "Testing Count"
puts i.count==1 && i.count == 2 && i.count == 3 ?'Success':'Failure'

puts "Testing count resets correctly"
ii = Legs.new('localhost',6425)
puts ii.count == 1 && ii.count == 2 && ii.count == 3 ?'Success':'Failure'
ii.close!
ii = nil

puts "Testing server disconnect worked correctly"
puts Legs.users.length == 1 ?'Success':'Failure'

puts "Testing async call..."
i.send_async!(:echo, 'Testing') do |r|
  puts r.result == 'Testing' ?'Success':'Failure'
end
sleep(0.5)

puts "Testing async error..."
i.send_async!(:error) do |r|
  begin
    v = r.result
    puts "Failure"
  rescue
    puts "Success"
  end
end
sleep(0.5)

puts "Testing regular error"
v = i.error rescue :good
puts v == :good ?'Success':'Failure'

puts "testing nofify!"
i.test_notify