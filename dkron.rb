#!/bin/ruby

require 'thor'
require 'json'
require 'pp'

# list all the cron servers here
$dkron_servers = ["host1","host2","host3"]
$whoami = `whoami`.chomp

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
                $dkron_servers.each { |server|
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
        }
        desc "remove cronserver", "Force leave a cron server"
        def remove(member)
                leader = getleader()
                if(member != leader)
                        puts ExecRestQuery(member,"XGET","leave")
                else
                        puts "cannot forcibly remove leader: #{leader}\n"
                end
        end

        desc "listmembers", "list all connected cron members"
        def listmembers
                init_host = GetInitHost()
                puts ExecRestQuery(init_host,"XGET","members?pretty")
        end

        desc "setcron <job_name> <time> <command> <run_on> [notify]","schedule the given job at the given time on the specified server"
        long_desc <<-LONGDESC
        dkron understands normal cron format. e.g."0 * * * * *"\n
        You may also schedule a job to execute at fixed intervals like this: "@every 1h30m10s"\n
        or at fixed intervals: "@at 2018-01-02T15:04:00Z"\n
        \n
        EXAMPLES:\n
    > $ setcron "get_hostname" "0 * * * * *" "/bin/hostname" "rhel6" stephenranjit
        \n
    > $ setcron "get_hostname" "@at 2018-01-02T15:04:00Z" "/bin/hostname" "rhel6" stephenranjit
        LONGDESC
        def setcron(name,time,command,runon,notify=$whoami)

                #construct hash
                #add the correct email address
                owner_email = "#{notify}\@company.com"
                job_hash = {
                        :name => "#{name}",
                        :command => "#{command}",
                        :shell => true,
                        :schedule => "#{time}",
                        :tags => {:type => "#{runon}:1"},
                        :retries => 0,
                        :dependent_jobs => nil,
                        :parent_job => "",
                        :owner => "#{notify}",
                        :owner_email => "#{owner_email}",
                        :disabled => false
                }

                init_host = GetInitHost()
                puts ExecRestQuery(init_host,"XPOST","jobs -d '"+job_hash.to_json+"'")
        end

        desc "delcron <job_name>","delete an existing cron job"
        def delcron(name)
                init_host = GetInitHost()
                puts ExecRestQuery(init_host,"XDELETE","jobs/#{name}")
        end

        desc "getcron <job_name>","get all or specified cron jobs"
        def getcron(name=nil)
                init_host = GetInitHost()
                name="/#{name}" if (name != nil)
                response = ExecRestQuery(init_host,"XGET","jobs#{name}")
                if(response != "")
                        jobs_array = JSON.parse(response)
                else
                        jobs_array = nil
                end
                puts "jobs:\n"
                pp jobs_array
                return jobs_array
        end

        desc "runcron <job_name>","on demand build"
        def runcron(name)
                init_host = GetInitHost()
                response = ExecRestQuery(init_host,"XPOST","jobs/#{name}")
                if(response == '{}')
                        if(getcron(name) == nil)
                                puts "invalid response: job #{name} does not exist\n"
                        else
                                puts "invalid response: job #{name} could not be run\n"
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