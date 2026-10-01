# frozen_string_literal: true

# Teaching example for immediate enqueue only. Invoke after the outer commit.
# A deferred enqueue returning a job is not evidence of queue acceptance.
module EnqueueExample
  def self.enqueue_now!(job)
    result = job.enqueue
    return result if result

    raise(job.enqueue_error || ActiveJob::EnqueueError.new("enqueue rejected"))
  end
end
