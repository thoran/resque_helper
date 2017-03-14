Resque.after_fork = Proc.new{ActiveRecord::Base.establish_connection}

if ENV['REDISTOGO_URL']
  uri = URI.parse(ENV['REDISTOGO_URL'])
  Resque.redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
end

Resque::Server.use(Rack::Auth::Basic) do |email, password|
  AdminUser.authenticate(email, password)
end

module Resque

  alias_method :empty_queue, :remove_queue
  alias_method :empty, :remove_queue

  def remove_queues
    Resque.queues.each do |queue|
      Resque.remove_queue(queue)
    end
  end
  alias_method :empty_queues, :remove_queues

  def kill_workers
    Resque.workers.each do |worker|
      Resque.kill(worker)
    end
  end

  def jobs_for_queue(queue_name)
    start, count = 0, Resque.size(queue_name)
    Resque.peek(queue_name, start, count)
  end

  def jobs(queue_name = nil)
    queues = queue_name ? [queue_name] : Resque.queues
    queues.collect do |queue|
      {queue => jobs_for_queue(queue)}
    end
  end

  def kill(worker)
    abort "** resque kill WORKER_ID" if worker.nil?
    worker = worker.to_s
    pid = worker.split(':')[1].to_i
    begin
      Process.kill("KILL", pid)
      puts "** killed #{worker}"
    rescue Errno::ESRCH
      puts "** worker #{worker} not running"
    end
    remove(worker)
  end

  def remove(worker)
    abort "** resque remove WORKER_ID" if worker.nil?
    Resque.remove_worker(worker)
    puts "** removed #{worker}"
  end

  def list
    if Resque.workers.any?
      Resque.workers.each do |worker|
        puts "#{worker} (#{worker.state})"
      end
    else
      puts "None"
    end
  end

  def unregister_workers
    Resque.workers.each{|worker| worker.unregister_worker}
  end

  def working_jobs
    Resque.workers.collect do |worker|
      worker.job
    end
  end

  def jobs_working_on(klass, *args)
    working_jobs.select do |working_job|
      job_working_on?(working_job, klass, *args)
    end
  end

  # boolean methods

  def job_working_on?(working_job, klass, *args)
    if args.empty?
      if working_job && working_job['payload']
        working_job['payload']['class'] == klass.to_s
      else
        false
      end
    else
      if working_job && working_job['payload']
        args_found = args.all?{|key,value| working_job['payload']['args'].first[key] == value}
        args_found && working_job['payload']['class'] == klass.to_s
      else
        false
      end
    end
  end

  def any_working_on?(klass, *args)
    working_jobs.any? do |working_job|
      job_working_on?(working_job, klass, *args)
    end
  end

  def all_working_on?(klass, *args)
    working_jobs.all? do |working_job|
      job_working_on?(working_job, klass, *args)
    end
  end

end

