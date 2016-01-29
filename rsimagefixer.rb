#!/usr/bin/env ruby
require 'rbvmomi'
require 'configparser'

$config = ConfigParser.new(ARGV[0])

def fix_image(template, image_id, pool, host)
	puts "About to work on #{template.name}"
	print "  Converting template #{template.name} to VM..."
	template.MarkAsVirtualMachine(:pool => pool, :host => host)
	puts "converted"

	print "  Updating extra config..."
	spec = RbVmomi::VIM.VirtualMachineConfigSpec({ "extraConfig" => [{ key: "rs.image", value: image_id }] })
	template.ReconfigVM_Task(:spec => spec)
	puts "updated"

	print "  Switching VM back to a template..."
	template.MarkAsTemplate()
	puts "switched"
end

def add_snapshot(template, pool, host)
        puts "About to work on #{template.name}"
        print "  Converting template #{template.name} to VM..."
        template.MarkAsVirtualMachine(:pool => pool, :host => host)
        puts "converted"

	print "  Creating snapshot..."
	template.CreateSnapshot_Task({ :name=>"Snapshot1a", :memory=>"false", :quiesce=>"false" })
	puts "snapped"
	print "  Switching VM back to a template..."
        template.MarkAsTemplate()
        puts "switched"
end

def findTemplates(item)
	@templates = Array.new
	item.children.each do |child|
		if defined? child.config.template and child.config.template == true
			puts "    Found template #{child.name}"
			@templates.push child
		elsif defined? child.childType
			@templates = @templates.concat findTemplates(child)
		end
	end
	return @templates
end

print "Connecting..."
vim = RbVmomi::VIM.connect host: $config["vsphere_host"], user: $config["vsphere_user"], password: $config["vsphere_password"], :insecure => true
puts "done"
vim.rootFolder.children.each do |dc|
	puts "Starting on datacenter #{dc.name}"
	templates = Array.new()
	hosts = Array.new
	print "Getting hosts..."
	dc.hostFolder.children.each do |cluster|
		hosts = hosts.concat cluster.host
	end
	if hosts.count == 0
		puts "failed... going on to next datacenter"
		next
	end
	puts "got"

	print "Searching resource pools..."
	begin
		pool = nil
		dc.hostFolder.children.each do |cluster|
			begin 
				pool = cluster.resourcePool.resourcePool.select{|p| p.name == $config["vsphere_resource_pool"]}.first
			rescue
				next
			end
		end
		puts "searched"
	rescue
		puts "failed... going on to next datacenter"
		next
	end


	puts "Looking for templates..."
	templates = findTemplates(dc.vmFolder)

	templates.each do |template|
		id = template.instance_variable_get(:@ref)
		begin
			rsimage = template.config.extraConfig.select{|prop|  prop.key == "rs.image" }.first.value
		rescue
			rsimage = nil
		end

		if id == rsimage
			puts  "OK    - #{template.name} has id:#{id}, and rs.image:#{rsimage}"
		else
			puts "ERROR - #{template.name} has id:#{id}, and rs.image:#{rsimage}"
			puts "  Fixing it now"
			hosts.each do |host|
				begin
					fix_image(template, id, pool, host)
					break
				rescue
					puts "    #{host.name} failed, trying another"
				end
			end
		end

		if template.snapshot == nil
			puts "  No snapshots found for #{template.name}"
			hosts.each do |host|
				begin
					add_snapshot(template, pool, host)
					break
				rescue
					puts "    #{host.name} failed, trying another"
				end
			end
		end
	end
end


