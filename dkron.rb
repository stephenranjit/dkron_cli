#!/bin/ruby

require 'thor'
require 'json'
require 'pp'
$whoami = `whoami`.chomp
$config_path = "./dkron.config"

class Dkron < Thor

        no_commands{
        def ExecRestQuery(server,type,query)
                dkron_rest_url = "http://#{server}:8080/v1/#{query}"
                rest_cmd = "curl -m 2 -s -#{type} #{dkron_rest_url}"
                puts "rest_cmd: #{rest_cmd}\n";
                rest_cmd_response = `#{rest_cmd}`.chomp
                puts "rest_cmd_response: #{rest_cmd_response}\n"
                return rest_cmd_response
        end

        def GetInitHost
		$dkron_servers = read_config()["dkron_servers"]
                $dkron_servers.each { |server|
			puts "checking #{server}...\n"
                        if(ExecRestQuery(server,"XGET","") != "")
                                $live_host = server
                                break
                        end
                }
                if(! $live_host)
                        abort("no hosts to run. exiting.")
                end
                puts "Init Host: #{$live_host}\n";
                return $live_host
        end

	def read_config()
		if(! File.file?($config_path))
			puts "Could not find #{$config_path}. Please configure the tool before use\n"
			exit
		end
		dkron_config_json = File.read($config_path)
                dkron_config_hash = JSON.parse(dkron_config_json)
		return(dkron_config_hash)
	end
        
	def toggle_state(job_name,state)
		cron_details=getcron(job_name)
                cron_details[:disabled]=state
                init_host = GetInitHost()
                puts ExecRestQuery(init_host,"XPOST","jobs -d '"+cron_details.to_json+"'")
	end

	}


	desc "configure","setup config file with variables"
	option :servers, :required => true, :type => :array, :aliases => :s
	def configure()
		setup_hash = {:dkron_servers => options[:servers]}
		File.open($config_path, 'w') { |config| config.write(setup_hash.to_json) }
	end
	
        desc "remove", "Force leave a cron server"
	option :server, :required => true, :aliases => :s
        def remove()
                leader = getleader()
                if(options[:server] != leader)
                        puts ExecRestQuery(options[:server],"XGET","leave")
                else
                        puts "cannot forcibly remove leader: #{leader}\n"
                end
        end

        desc "listmembers", "list all connected cron members"
        def listmembers
                init_host = GetInitHost()
                puts ExecRestQuery(init_host,"XGET","members?pretty")
        end

        desc "setcron","schedule the given job at the given time on the specified server\n"
        long_desc <<-LONGDESC
        dkron understands normal cron format. e.g."0 * * * * *"\n
        You may also schedule a job to execute at fixed intervals like this: "@every 1h30m10s"\n
        or at fixed intervals: "@at 2018-01-02T15:04:00Z"\n
        \n
        EXAMPLES:\n
    > #{$0} setcron --job-name="get_hostname" --time="0 * * * * *" --command="/bin/hostname" --runon="rhel6" --notify=stephenranjit@co.com --parent=job1 --dependent=job2
        \n
    > #{$0} setcron --job-name="get_hostname" --time="@at 2018-01-02T15:04:00Z" --command="/bin/hostname" --runon="rhel6" --notify=stephenranjit@co.com --parent=job1 --dependent=job2
        LONGDESC
	option :job_name, :required => true, :aliases => :j
	option :time, :required => true, :aliases => :t
	option :command, :required => true, :aliases => :c
	option :runon, :required => true, :aliases => :r
	option :dependent, :default => nil, :type => :array, :aliases => :d
	option :parent, :aliases => :p
	option :notify, :aliases => :n
        def setcron()
                job_hash = {
                        :name => options[:job_name],
                        :command => options[:command],
                        :shell => true,
                        :schedule => options[:time],
                        :tags => {:type => "#{options[:runon]}:1"},
                        :retries => 0,
                        :dependent_jobs => options[:dependent],
                        :parent_job => options[:parent],
                        :owner => options[:notify],
                        :owner_email => options[:notify],
                        :disabled => false
                }

                init_host = GetInitHost()
                puts ExecRestQuery(init_host,"XPOST","jobs -d '"+job_hash.to_json+"'")
        end

	desc "disablecron","disable an existing cron job"
        option :job_name, :required => true, :aliases => :j
        def disablecron()
        	toggle_state(options[:job_name],"true")
	end

	desc "enaablecron","enable an existing cron job"
        option :job_name, :required => true, :aliases => :j
        def enaablecron()
                toggle_state(options[:job_name],"false")
        end

        desc "delcron","delete an existing cron job"
	option :job_name, :type => :array, :required => true, :aliases => :j
        def delcron()
                init_host = GetInitHost()
		options[:job_name].each { |job_name|
	                puts ExecRestQuery(init_host,"XDELETE","jobs/#{job_name}")
		}
        end

        desc "getcron","get all or specified cron jobs"
	option :job_name, :default => nil, :aliases => :j
        def getcron(job_name=nil)
                init_host = GetInitHost()
		if(job_name != nil)
			job_name="jobs/#{job_name}"
			puts "job_name = #{job_name}\n"
                elsif(options[:job_name] != nil)
			job_name="jobs/#{options[:job_name]}"
		else
			job_name="jobs"
		end 
                response = ExecRestQuery(init_host,"XGET","#{job_name}")
                if(response != "")
                        jobs_array = JSON.parse(response)
                else
                        jobs_array = nil
                end
                puts "jobs:\n"
                pp jobs_array
                return jobs_array
        end

	desc "getresult","get executions"
	option :job_name, :required => true, :aliases => :j
	def getresult
		init_host = GetInitHost()
		response = ExecRestQuery(init_host,"XGET","executions/#{options[:job_name]}")
		if(response != "")
                        results_array = JSON.parse(response)
                else
                        results_array = nil
                end
                pp results_array

	end

        desc "runcron","on demand build"
	option :job_name, :required => true, :aliases => :j
        def runcron()
                init_host = GetInitHost()
                response = ExecRestQuery(init_host,"XPOST","jobs/#{options[:job_name]}")
                if(response == '{}')
                        if(getcron(options[:job_name]) == nil)
                                puts "invalid response: job #{options[:job_name]} does not exist\n"
                        else
                                puts "invalid response: job #{options[:job_name]} could not be run\n"
                        end
                end
        end

        desc "getleader","get dkron cluster leader"
        def getleader
                init_host = GetInitHost()
                leader_hash = JSON.parse(ExecRestQuery(init_host,"XGET","leader?pretty"))
                puts leader_hash["Name"]
                return leader_hash["Name"]
        end
end

Dkron.start(ARGV)
