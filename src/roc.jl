using .AMDGPU
import .AMDGPU: ROCDevice

struct ROCArrayDeviceProc <: Dagger.Processor
    owner::Int
    device::ROCDevice
end
@gpuproc(ROCArrayDeviceProc, ROCArray)
Dagger.get_parent(proc::ROCArrayDeviceProc) = Dagger.OSProc(proc.owner)

Dagger.execute!(proc::ROCArrayDeviceProc, func, args...) = func(args...)

function Dagger.execute!(proc::ROCArrayDeviceProc, func, args...)
    tls = Dagger.get_tls()
    task = Threads.@spawn begin
        Dagger.set_tls!(tls)
        # FIXME: Set task-local device
        func(args...)
    end
    try
        fetch(task)
    catch err
        @static if VERSION >= v"1.1"
            stk = Base.catch_stack(task)
            err, frames = stk[1]
            rethrow(CapturedException(err, frames))
        else
            rethrow(task.result)
        end
    end
end
Base.show(io::IO, proc::ROCArrayDeviceProc) =
    print(io, "ROCArrayDeviceProc on worker $(proc.owner), agent $(proc.device)")

processor(::Val{:ROC}) = ROCArrayDeviceProc
cancompute(::Val{:ROC}) = AMDGPU.functional()
kernel_backend(proc::ROCArrayDeviceProc) = proc.device

if AMDGPU.configured
    for device in AMDGPU.devices()
        Dagger.add_processor_callback!("rocarray_device_$(AMDGPU.device_id(device))") do
            ROCArrayDeviceProc(myid(), device)
        end
    end
end
