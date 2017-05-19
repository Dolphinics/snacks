#include <cuda.h>
#include <sisci_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

sci_error_t err;
sci_desc_t sd;
unsigned nodeid;

__global__ void kernel(void* src, void* dst)
{
    *((int*) dst) = *((int*) src);
    *((int*) src) = 0;
}

void server(unsigned segid)
{
    sci_local_segment_t seg;
    SCICreateSegment(sd, &seg, segid, 0x1000, NULL, NULL, 0, &err);

    SCIPrepareSegment(seg, 0, 0, &err);
    SCISetSegmentAvailable(seg, 0, 0, &err);

    sci_map_t m;
    void* ptr = SCIMapLocalSegment(seg, &m, 0, 0x1000, NULL, 0, &err);

    while (1)
    {
        sleep(2);
        printf("%x\n", *((int*) ptr));
        (*((volatile int*) ptr))++;
    }
}


void client(unsigned nodeid, unsigned segid)
{
    sci_remote_segment_t seg;
    SCIConnectSegment(sd, &seg, nodeid, segid, 0, NULL, NULL, SCI_INFINITE_TIMEOUT, 0, &err);

    sci_map_t m;
    volatile void* ptr = SCIMapRemoteSegment(seg, &m, 0, 0x1000, NULL, 0, &err);
    //*((volatile int*) ptr) = 0xdede;

    SCIRegisterPCIeRequester(sd, 0, 1, 0, SCI_FLAG_PCIE_REQUESTER_GLOBAL, &err);
    if (err != SCI_ERR_OK)
    {
        printf("oh noes\n");
    }
    
    cudaSetDevice(0);

    fprintf(stderr, "%p\n", (void*) ptr);

    cudaError_t cudaerr = cudaHostRegister((void*) ptr, 0x1000, cudaHostRegisterIoMemory | cudaHostRegisterMapped);
    if (cudaerr != cudaSuccess)
    {
        fprintf(stderr, "%s\n", cudaGetErrorString(cudaerr));
    }

    void* devp;
    cudaerr = cudaHostGetDevicePointer(&devp, (void*) ptr, 0);
    if (cudaerr != cudaSuccess)
    {
        fprintf(stderr, "%s\n", cudaGetErrorString(cudaerr));
    }

    void* devp2;
    cudaMalloc(&devp2, sizeof(int));

    kernel<<<1, 1>>>(devp, devp2);

    int value = 0;
    cudaMemcpy(&value, devp2, sizeof(int), cudaMemcpyDeviceToHost);
    fprintf(stderr, "%x\n", value);

    sleep(5);
}


int main(int argc, char** argv)
{
    unsigned remote_nodeid = 0;
    unsigned remote_segid = 0;
    unsigned local_segid = 0;

    SCIInitialize(0, &err);

    SCIOpen(&sd, 0, &err);

    SCIGetLocalNodeId(0, &nodeid, 0, &err);
    remote_nodeid = nodeid;

    if (argc > 2)
    {
        remote_nodeid = atoi(argv[1]);
        remote_segid = atoi(argv[2]);
    }
    else if (argc > 1)
    {
        local_segid = atoi(argv[1]);
    }
    else
    {
        fprintf(stderr, "Usage: %s <remote node> <remote segment> | %s <local segment>\n", argv[0], argv[0]);
        return 1;
    }

    if (remote_nodeid != nodeid)
    {
        client(remote_nodeid, remote_segid);
    }
    else
    {
        printf("this node: %u, this segment: %u\n", nodeid, local_segid);
        server(local_segid);
    }

    return 0;
}
