namespace Treasure.Renderer;

using System;
using System.Diagnostics;
using SDL3;

/* @todo
- Do not free and allocate transfers and buffers all the time. Reuse them.
- Think about overlapping GPU work. Now everything happens at the end of
the frame in the final command buffer.
*/

enum GPUBATCHType
{
    Unknown,
    MeshVertices,
    ModelInstances,
    Poses
}

struct GPUBATCHTarget
{
    public GPUBATCHType type;
    public MATERIALKey material_key;
    public MODELKey model_key;

    public static bool Match(GPUBATCHTarget a, GPUBATCHTarget b)
    {
        if (a.type == b.type)
        {
            if (a.type == .MeshVertices)
            {
                return a.material_key.Match(b.material_key);
            }

            if (a.type == .ModelInstances)
            {
                return a.material_key.Match(b.material_key) &&
                    a.model_key.Match(b.model_key);
            }

            return a.model_key.Match(b.model_key);
        }
        return false;
    }
}

class GPUBATCHTransfer
{
    public SDL_GPUTransferBuffer* handle;
    public uint32 cap; // in bytes

    public uint32 used; // in bytes
    public void* mapped_memory;
    public GPUBATCHTransfer next;

    public void TransferUnmap(SDL_GPUDevice* device)
    {
        Debug.Assert(mapped_memory != null);
        SDL_UnmapGPUTransferBuffer(device, handle);
        mapped_memory = null;
    }
}

class GPUBATCHBuffer
{
    public SDL_GPUBuffer* handle;
    public uint32 cap;
    public GPUBATCHBuffer next; // used by free list only
}

class GPUBatch
{
    // can live between frames
    public GPUBATCHTarget target;
    public GPUBATCHBuffer buffer;

    // cleared after every frame
    public GPUBATCHTransfer transfer_first;
    public GPUBATCHTransfer transfer_last;
    public uint32 total_used;
    public uint32 element_count;
}

class GPUBATCHState
{
    private append BumpAllocator arena = .(); // for allocating GPU_TransferStorage, GPU_BufferStorage

    // these free list don't hold any GPU resources, just a way to reuse CPU memory
    public GPUBATCHTransfer free_transfers;
    public GPUBATCHBuffer free_buffers;

    public GPUBatch[2048] batches;
    public uint32 batches_count;

    public void Init(SDL_GPUDevice* device)
    {
        // reserve poses batch
        this.batches_count += 1;
        this.batches[0].target.type = .Poses;
        this.AllocBuffer(device, 16,
            SDL_GPUBufferUsageFlags.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            out this.batches[0].buffer);
    }

    public void Deinit(SDL_GPUDevice* device)
    {
        for (int batch_index = 0; batch_index < this.batches_count; batch_index++)
        {
            if (this.batches[batch_index].buffer != null)
            {
                SDL_ReleaseGPUBuffer(device, this.batches[batch_index].buffer.handle);
            }
        }
    }

    private uint32 CeilPow2(uint32 vo)
    {
        uint32 v = vo;
        v--;
        v |= v >> 1;
        v |= v >> 2;
        v |= v >> 4;
        v |= v >> 8;
        v |= v >> 16;
        v++;
        return v;
    }

    public bool FindBundle(GPUBATCHTarget target, out GPUBatch batch)
    {
        batch = null;
        for (int it = 0; it < this.batches_count; it++)
        {
            if (GPUBATCHTarget.Match(this.batches[it].target, target))
            {
                batch = this.batches[it];
                return true;
            }
        }
        return false;
    }

    public void FindOrCreateBundle(GPUBATCHTarget target, out GPUBatch batch)
    {
        if (FindBundle(target, out batch))
        {
            return;
        }
        Debug.Assert(this.batches_count < this.batches.Count);

        batch = this.batches[this.batches_count];
        this.batches_count += 1;
        // We don't need to clear batch since
        // batches array is zero initialized on game launch.
        // + G.gpu.mem.batches_count isn't reset between frames.
        batch.target = target;
        return;
    }

    public bool TransferCreate(SDL_GPUDevice* device, GPUBatch batch,
        uint32 size, out GPUBATCHTransfer result)
    {
        // Calculate rounded-up alloc_size
        uint32 alloc_size = this.CeilPow2(size * 2);
        if (batch.buffer != null)
        {
            alloc_size = Math.Max(alloc_size, batch.buffer.cap);
        }

        // Reclaim GPU_BATCH_TransferStorage from free list or allocate a new one
        // Zero initialize it
        result = this.free_transfers;
        {
            if (result != null)
            {
                this.free_transfers = this.free_transfers.next;
            }
            else
            {
                result = new:arena GPUBATCHTransfer();
            }
        }

        // GPU alloc new transfer buffer and map it
        SDL_GPUTransferBufferCreateInfo transfer_info = SDL_GPUTransferBufferCreateInfo()
        {
            usage = .SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            size = alloc_size
        };
        result.handle = SDL_CreateGPUTransferBuffer(device, &transfer_info);
        result.cap = alloc_size;
        result.mapped_memory = SDL_MapGPUTransferBuffer(device, result.handle, false);

        // Chain result into its GPU_BATCH_Entry
        {
            if (batch.transfer_last != null)
            {
                batch.transfer_last.next = result;
            }    
            
            batch.transfer_last = result;

            if (batch.transfer_first != null)
            {
                batch.transfer_first = result;
            }    
            
        }

        return true;
    }

    public void TransferGetMappedMemory(SDL_GPUDevice* device, GPUBatch batch,
        uint32 size, uint32 elem_count, out void* result)
    {
        batch.element_count += elem_count;

        if (batch.transfer_last != null)
        {
            Debug.Assert(batch.transfer_last.cap > batch.transfer_last.used);
            if (batch.transfer_last.cap - batch.transfer_last.used < size)
            {
                batch.transfer_last.TransferUnmap(device);
                batch.transfer_last = null;
            }
        }

        if (batch.transfer_last == null)
        {
            TransferCreate(device, batch, size, out batch.transfer_last);
        }

        result = (uint8*)batch.transfer_last.mapped_memory + batch.transfer_last.used;
        batch.total_used += size;
        batch.transfer_last.used += size;
    }

    //
    public void AllocBuffer(SDL_GPUDevice* device, uint32 alloc_size,
        SDL_GPUBufferUsageFlags usage, out GPUBATCHBuffer buffer)
    {
        buffer = this.free_buffers;
        {
            if (buffer != null)
            {
                this.free_buffers = this.free_buffers.next;
            }
            else
            {
                buffer = new:arena GPUBATCHBuffer();
            }
        }

        SDL_GPUBufferCreateInfo buffer_info = SDL_GPUBufferCreateInfo()
        {
            usage = usage, size = alloc_size
        };
        buffer.handle = SDL_CreateGPUBuffer(device, &buffer_info);
        buffer.cap = alloc_size;
    }

    public void UploadBatch(SDL_GPUDevice* device, SDL_GPUCopyPass* copy_pass, GPUBatch batch)
    {
        if (batch.total_used > 0)
        {
            // Check if current buffer is big enough.
            // Free it if it's too small.
            if (batch.buffer != null)
            {
                if (batch.buffer.cap < batch.total_used)
                {
                    SDL_ReleaseGPUBuffer(device, batch.buffer.handle);

                    // Move BufferStorage to free list
                    batch.buffer.next = this.free_buffers;
                    this.free_buffers = batch.buffer;
                    batch.buffer = null;
                }
            }

            // Allocate buffer
            if (batch.buffer == null)
            {
                SDL_GPUBufferUsageFlags usage = 0;
                if (batch.target.type == .MeshVertices)
                {
                    usage |= SDL_GPUBufferUsageFlags.SDL_GPU_BUFFERUSAGE_VERTEX;
                }
                else
                {
                    usage |= SDL_GPUBufferUsageFlags.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ;
                }

                this.AllocBuffer(device, this.CeilPow2(batch.total_used * 2), usage, out batch.buffer);
            }

            // Transfers -> Buffer
            {
                uint32 offset = 0;
                GPUBATCHTransfer transfer = batch.transfer_first;
                while (transfer != null)
                {
                    SDL_GPUTransferBufferLocation source = SDL_GPUTransferBufferLocation()
                    {
                        transfer_buffer = transfer.handle
                    };
                    SDL_GPUBufferRegion destination = SDL_GPUBufferRegion()
                    {
                        buffer = batch.buffer.handle,
                        offset = offset,
                        size = transfer.used
                    };
                    SDL_UploadToGPUBuffer(copy_pass, &source, &destination, false);

                    offset += transfer.used;
                    transfer = transfer.next;
                }
            }

            // Free transfers
            GPUBATCHTransfer transfer = batch.transfer_first;
            while (transfer != null)
            {
                GPUBATCHTransfer next = transfer.next;

                SDL_ReleaseGPUTransferBuffer(device, transfer.handle);
                transfer.next = this.free_transfers;
                this.free_transfers = transfer;

                transfer = next;
            }

            // clear batch transfer links
            batch.transfer_first = null;
            batch.transfer_last = null;
        }
    }

    public void TransferUploadBytes(SDL_GPUDevice* device,
        GPUBatch batch, void* data, uint32 size, uint32 elem_count)
    {
        void* dst = null;
        this.TransferGetMappedMemory(device, batch, size, elem_count, out dst);
         
        Internal.MemCpy(dst, data, size);
    }

    public void UploadAllBatches(SDL_GPUDevice* device, SDL_GPUCommandBuffer* cmd)
    {
        SDL_GPUCopyPass* copy_pass = SDL_BeginGPUCopyPass(cmd);

        for (uint32 batch_index = 0; batch_index < this.batches_count; batch_index++)
        {
            GPUBatch batch = this.batches[batch_index];
            this.UploadBatch(device, copy_pass, batch);
        }

        SDL_EndGPUCopyPass(copy_pass);
    }

    public void PostFrame()
    {
        for (uint32 batch_index = 0; batch_index < this.batches_count; batch_index++)
        {
            GPUBatch batch = this.batches[batch_index];
            Debug.Assert(batch.transfer_first == null);
            Debug.Assert(batch.transfer_last == null);
            batch.total_used = 0;
            batch.element_count = 0;
        }
    }

    public void GetPosesBatch(out Span<GPUBatch> batch)
    {
        batch = batches;
    }
}
