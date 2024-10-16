module va_toolbox.memory;

import va_toolbox.linked_list;

bool DEBUG = false;

private void logF(T...)(T args) {
    import std.stdio : writef, stdout;
    if (DEBUG) {
        writef(args);
        stdout.flush;
    }
}

private void logFLine(T...)(T args) {
    import std.stdio : writefln, stdout;
    if (DEBUG) {
        writefln(args);
        stdout.flush;
    }
}


enum IPTRBITS = (void*).sizeof * 8;



import std.conv;
import core.stdc.string;
import std.bitmanip; //  toBigEndian
import std.exception;
import core.exception;

/****************************************************************************
** This are the COMPILE flags for basic debugging. The memory functions
** are one of most important functions in CaOS. They must be extremly
** stable.
*/
enum bool DEALLOC_PATTERN = true; // Enable block fills
enum bool ALLOC_PATTERN = true; // Enable block fills
enum bool BOUNDS_CHECKING = true; // Enable boundary checks

const ulong FILLPATTERN_ALLOC = 0xaaaaaaaaaaaaaaaa; // After block is allocated
const ulong FILLPATTERN_FREE = 0x5555555555555555; // After block is freed.

const auto FILLPATTERN_MUNGW1 = nativeToBigEndian(0xdeadbeefdeadbeef); // Before allocated block
const auto FILLPATTERN_MUNGW2 = nativeToBigEndian(0xcafecafecafecafe); // After allocated block.

static assert(FILLPATTERN_MUNGW1.length == size_t.sizeof, "Size mismatch.");

private size_t getMungwallExtraSize(int alignment) {
    size_t byteSize = 0;
    if (alignment) {
        if (alignment < MemHeader.MEM_BLOCKEXP)
            alignment = MemHeader.MEM_BLOCKEXP;
        byteSize += 1UL << alignment;
    } else
        byteSize += MemHeader.MEM_BLOCKSIZE; // We add a new block, keeping alignment as is
    byteSize += size_t.sizeof; // We need also some storage at the end
    return byteSize; // This is the extra size needed, rounded up by allocator as needed
}

private void* setupMungwall(void* memPtr, size_t byteSize, int alignment = 0) {
    // Note: byteSize already includes the extra size!
    // Note: memPtr is already modified for aligned and abs allocation.
    // Note: both value are used in allocator, and must be used for freeMem() later on

    //-- Add a MEM_BLOCKSIZE space and store MungWall and original addr and size
    auto tmpPtr = memPtr;
    if (alignment) {
        if (alignment < MemHeader.MEM_BLOCKEXP)
            alignment = MemHeader.MEM_BLOCKEXP;
        tmpPtr += 1UL << alignment;
    } else
        tmpPtr += MemHeader.MEM_BLOCKSIZE;

    auto lowerPtr = cast(size_t*) tmpPtr;
    lowerPtr[-3] = cast(size_t) memPtr; // Real allocAddr
    lowerPtr[-2] = byteSize; // Real length with mungs
    memcpy(&lowerPtr[-1], FILLPATTERN_MUNGW1.ptr, FILLPATTERN_MUNGW1.length);

    //-- Copy mungwall after end of data array. Removed
    void* upperPtr = tmpPtr + byteSize - getMungwallExtraSize(alignment);
    memcpy(upperPtr, FILLPATTERN_MUNGW2.ptr, FILLPATTERN_MUNGW2.length);

    return cast(void*) lowerPtr;
}

private void checkMungwall(ref void* mptr, ref size_t byteSize) {

    string dbgText() {
        import std.format : format;

        return format(
            "\n" ~
                "##########################################################################\n" ~
                "### FATAL bounds checking error in freeMem().\n" ~
                "### memoryPtr = %0x and size %x :\n" ~
                "### Head mungwall: %(%02X%), Tail mungwall: %(%02X%)\n" ~
                "##########################################################################\n",
            mptr, byteSize,
            *cast(ubyte[size_t.sizeof]*)(mptr - size_t.sizeof),
            *cast(ubyte[size_t.sizeof]*)(mptr + byteSize)
        );
    }

    size_t* lowerPtr = cast(size_t*)(mptr);
    assert(memcmp(&lowerPtr[-1], FILLPATTERN_MUNGW1.ptr, size_t.sizeof) == 0, __FUNCTION__ ~ ": Mung1 corrupted." ~ dbgText());
    ubyte* upperPtr = cast(ubyte*)(mptr + byteSize);
    assert(memcmp(upperPtr, FILLPATTERN_MUNGW2.ptr, size_t.sizeof) == 0, __FUNCTION__ ~ ": Mung2 corrupted." ~ dbgText());

    // Clear Mungwall patterns
    lowerPtr[-1] = FILLPATTERN_FREE;
    memcpy(upperPtr, &FILLPATTERN_FREE, size_t.sizeof);

    // Restore the original memory address, and modify
    mptr = cast(void*) lowerPtr[-3];
    byteSize = lowerPtr[-2];
}

/** Memory Requirement Types (see AllocMem() )*/
enum MemFlags : uint {
    MEMF_ANY = (0), // Any type of memory will do
    MEMF_PUBLIC = (1L << 0), // Nonswapable public memory
    MEMF_FAST = (1L << 1), // This is extrafast memory
    MEMF_VIDEO = (1L << 2), // Some gfx system allow this
    MEMF_VIRTUAL = (1L << 3), // If possible use swapable memory

    MEMF_PERMANENT = (1L << 15), // Memory that does not go away at RESET
    // (Is available at Main() with old content)

    MEMF_MASKFLAGS = 0x0000ffff, // The lower 16 bits are memory attributes

    // The following flags are used for special allocatior operation. Use them as you need.

    MEMF_CLEAR = (1L << 16), // AllocMem: null out area before return
    MEMF_LARGEST = (1L << 17), // AvailMem: return the largest chunk size
    MEMF_REVERSE = (1L << 18), // AllocMem: allocate from the top down
    MEMF_TOTAL = (1L << 19), // AvailMem: return total size of memory
    MEMF_ALIGN = (1L << 20), // allocateAbs: use alignment mask instead of location

    MEMF_NO_EXPUNGE = (1L << 31) // AllocMem: Do not cause expunge on failure

}

alias MEMHANDLERCODE = int function(Memory m, MemHandler* mh, MemHandlerData* data);

/** MemHandlerData
    * Note:  This structures are *READ ONLY*
    */
struct MemHandler {
    ListNode mmh_Node;
    uint mmh_Flags; // Execution modes
    void* mmh_UserData; // handler data segment
    MEMHANDLERCODE mmh_UserCode; // handler code
}

struct MemHandlerData {
    size_t mhd_RequestSize; // Requested allocation size
    size_t mhd_RequestAlign; // Requested allocation aligment
    size_t mhd_RequestFlags; // Requested allocation flags
    size_t mhd_Flags; // Flags (see below)
}

enum MEMHF_RECYCLE = (1L << 0); // 0==First time, 1==recycle

enum SYSMEMHANDLERPRI = (-0x1000); // The system.lib internal handler

/*************************************************************************
** Low Memory handler STATUS return values.
**
**    Return MEM_DID_NOTHING, if you couldn't free some memory.
**    Return MEM_TRY_AGAIN, you freed some memory, but can free more.
**    Return MEM_ALL_DONE if you can't free more memory.
*/
enum MEM_DID_NOTHING = (0); // Nothing we could do...
enum MEM_ALL_DONE = (-1); // We did all we could do
enum MEM_TRY_AGAIN = (1); // We did some, try the allocation again
alias STATUS = int;

import core.sync.mutex;

/** MemHeader */
struct MemHeader {
    ListNode mh_Node; // Allows to type, priorize and name the memory
    MemFlags mh_Attributes; // characteristics of this memory
    size_t mh_Free; // total number of free bytes
    size_t mh_Total; // maximum possible free bytes.
    void* mh_Lower; // lower memory bound
    void* mh_Upper; // upper memory bound+1
    TinyHead mh_ChunkList; // list of free memory regions

    /** MemChunk - The node of a free mem segment */
    struct MemChunk {
        TinyNode mc_Node;
        size_t mc_Bytes;
    }
    /* Alignment rules for memory. The Block must be large enough to contain
    ** a MemChunk structure, as well a 2^n value for fast masking.
    */
    enum MEM_BLOCKEXP = 5;
    enum MEM_BLOCKSIZE = 2 ^^ MEM_BLOCKEXP;
    enum MEM_BLOCKMASK = MEM_BLOCKSIZE - 1;
    private static T alignValDown(T)(T val, const int alignexp) {
        size_t sz = cast(size_t)(2 ^^ alignexp);
        size_t msk = cast(T)(sz - 1);
        return cast(T)(cast(size_t) val & ~msk);
    }

    private static T alignValUp(T)(T val, const int alignexp) {
        size_t sz = cast(size_t)(2 ^^ alignexp);
        size_t msk = cast(T)(sz - 1);
        return cast(T)((cast(size_t) val + msk) & ~msk);
    }

    /** initMemList -- Init a memheader structure
    *
    *	Prepares a MemHeader structure for other memory functions. The
    *	MemHeader is created at the begin of the memory range. The rest of
    *   the memory is used to create a linked list of free mem chunks.
    *
    *	This code is called by addMemHeader() itself.
    *
    * Params:
    *	size = size of memory range to add
    *	attributes = memory attributes to associate with memory range
    *	pri = ln_Priority for this memory range
    *	membase = base address of memory to add
    *	name = a symbolic name for this memory range
    *
    * Returns:
    *	A usable MemHeader for the given memory range.
    *
    * See:
    *	addMemHeader(), remMemHeader(), Allocate(), deallocate()
    */
    static MemHeader* initMemHeader(size_t size, MemFlags attributes, short pri, void* membase, string name) {
        logFLine(__FUNCTION__ ~ "( %08x,%08x,%08x,%08x,%s)", size, attributes, pri, membase, name);

        /* As our memory allocator needs special alignments, we must now calculate
        ** the start for the first free memory chunk first.
        */
        auto mhp = cast(MemHeader*) membase; // The new memory starts with this struct
        auto tmpAddr = cast(size_t)(mhp + 1); // Get the end of the header struct
        tmpAddr = alignValUp(tmpAddr, MEM_BLOCKEXP); // Round up to 2^n boundary
        auto mcp = cast(MemChunk*) tmpAddr; // This is the location of first mem chunk

        auto headerSize = tmpAddr - cast(size_t) mhp; // Get offset from start of memory
        logFLine("mh.sz = %x. mhp = %x, mcp = %x, hdrSz = %x", MemHeader.sizeof, mhp, mcp, headerSize);
        size -= headerSize; // sub difference from size
        size &= ~MEM_BLOCKMASK; // Round down to boundary

        /* And now inititalize the MemHeader with the corrected values. */
        mhp.mh_Node = ListNode(null, null, ListNodeType.LNT_MEMORY, pri, name);
        mhp.mh_Attributes = attributes; // Our memory attributes.
        mhp.mh_Free = size; // And total free size
        mhp.mh_Total = size; // remember it
        mhp.mh_Lower = mcp; // Memory boundaries
        mhp.mh_Upper = (cast(void*) mcp + size);
        mhp.mh_ChunkList.initListHead; // Start of first MemChunks

        if (ALLOC_PATTERN)
            (cast(ulong*) mcp)[0 .. size / ulong.sizeof] = FILLPATTERN_FREE; // Debugging aid.

        /*************************************************************************
        ** Now prepare the first MemChunk
        */
        mcp.mc_Bytes = size; // Number of bytes in this chunk (all bytes in this case)

        mcp.mc_Node = TinyNode();
        mhp.mh_ChunkList.addNode(mcp.mc_Node); // Add to our list

        return mhp;
    }

    /** Allocate -- Allocate from a MemHeader managed memory
    *
    *	This function is used to allocate blocks of memory from a given
    *	private free memory pool (as specified by a MemHeader and its
    *	memory chunk list).  Allocate will return the first free block that
    *	is greater than or equal to the requested size, either from begin or
    *   end of the freelist as requested by MEMF_REVERSE.
    *
    *	All blocks, whether free or allocated, will be block aligned;
    *	hence, all allocation sizes are rounded up to the next block even
    *	value (e.g. the minimum allocation resolution is MEM_BLOCKSIZE
    *	bytes.  A request for MEM_BLOCKSIZE bytes will use up exactly
    *	MEM_BLOCKSIZE bytes.  A	request for MEM_BLOCKSIZE-1 bytes will
    *	also use up exactly MEM_BLOCKSIZE bytes.).
    *
    *	This function can be used to manage an application's internal data
    *	memory.  Note that no arbitration of the MemHeader and associated
    *	free chunk list is done.  You must be the owner before calling
    *	Allocate.
    *
    *	This function will allocate accordingly	to your MEMF_#? flags.
    *
    * Params:
    *	byteSize = requested byte size. The size is rounded up to the
    *      next MEM_BLOCKSIZE boundary.
    *	flags = flags to use for allocation
    *
    * Returns:
    *	null on failure, or the pointer to your allocated memory. The memory
    *   is aligned to MEM_BLOCKSIZE boundaries.
    *
    * See:
    *	initMemList(), addMemHeader(), remMemHeader(), allocateAbs(), deallocate()
    */
    void* allocate(size_t byteSize, MemFlags flags) {
        void* mymem = null;
        logF(__FUNCTION__ ~ "( %08x,%08x,%08x ) = ", &this, byteSize, flags);

        if (byteSize && this.mh_Free >= byteSize) {
            /*********************************************************************
            ** Round up byteSize to next block boundary
            */
            byteSize = alignValUp(byteSize, MEM_BLOCKEXP);

            /* Now traverse the list to find a memchunk large enough for our
            ** allocation. We can allocate from the front or end of list.
            */
            MemChunk* currmc;
            if (flags & MemFlags.MEMF_REVERSE)
                currmc = cast(MemChunk*)(this.mh_ChunkList.getTailPred);
            else
                currmc = cast(MemChunk*)(this.mh_ChunkList.getHeadSucc);

            while (currmc.mc_Node.isNodeReal) {
                if (currmc.mc_Bytes >= byteSize)
                    break;

                if (flags & MemFlags.MEMF_REVERSE)
                    currmc = cast(MemChunk*) currmc.mc_Node.getPrevNode; // Ok, then get previous free node
                else
                    currmc = cast(MemChunk*) currmc.mc_Node.getNextNode; // Ok, then get next free node
            }
            /* Here at least one mc must be found, or there is no memory chunk
            ** large enough for our request.
            */
            if (currmc.mc_Node.isNodeReal) {
                /* We found a matching memchunk. So we will take the needed space from
                ** this memchunk for our allocation. We must link the prev node to
                ** a newly created memchunk after our allocation, or if we allocate
                ** reversly, we can take the memory from the end of the current chunk.
                **
                ** There is trival case: Our request exactly fits the free chunk size.
                ** For both allocation mode, we can simply remove the free chunk from
                ** its list.
                **
                ** The next following code sequence expects the address of the
                ** allocated area in mymem.
                */
                if (currmc.mc_Bytes == byteSize) //** Trivial case
                {
                    mymem = cast(void*) currmc.mc_Node.remNode;
                } else //** Nontrival case
                {
                    if (flags & MemFlags.MEMF_REVERSE) //** Allocation mode reverse ?
                    {
                        /* cut some space from the end of the current free chunk */
                        currmc.mc_Bytes -= byteSize; //** Shorten MC
                        mymem = cast(MemChunk*)(cast(void*) currmc + currmc.mc_Bytes);

                    } else //** Normal allocation mode.
                    {
                        /* cut some space from the start of a mem chunk. We must
                        ** create a new node at currnode + byteSize, and remove the
                        ** rest of the remaining currmc.
                        */
                        auto newmc = cast(MemChunk*)(cast(void*) currmc + byteSize);
                        newmc.mc_Bytes = currmc.mc_Bytes - byteSize;

                        newmc.mc_Node = TinyNode(); // Ensure, that ptr are null
                        this.mh_ChunkList.addNode(newmc.mc_Node, &currmc.mc_Node);

                        mymem = cast(void*) currmc.mc_Node.remNode;
                    }
                }

                /* Now postprocess the memheader structure amd allocated memory. */
                this.mh_Free -= byteSize; // Correct the free size.

                // Now fulfill some our users additional wishes
                if (flags & MemFlags.MEMF_CLEAR)
                    (cast(ubyte*) mymem)[0 .. alignValUp(byteSize, MEM_BLOCKEXP)] = 0;
                else if (ALLOC_PATTERN)
                    (cast(ulong*) mymem)[0 .. alignValUp(byteSize, MEM_BLOCKEXP) / ulong.sizeof] = FILLPATTERN_ALLOC;
            }
        }
        logFLine("%08x", mymem);
        return mymem;
    }

    /** allocateAbs -- Allocate absolute or aligned memory chunk from MemHeader managed memory
    *
    *	Allocates absolute or aligned memory from the given MemHeader.
    *
    *	All blocks, whether free or allocated, will be block aligned;
    *	hence, all allocation sizes are rounded up to the next block even
    *	value (e.g. the minimum allocation resolution is MEM_BLOCKSIZE
    *	bytes.  A request for MEM_BLOCKSIZE bytes will use up exactly
    *	MEM_BLOCKSIZE bytes.  A	request for MEM_BLOCKSIZE-1 bytes will
    *	also use up exactly MEM_BLOCKSIZE bytes.).
    *
    *	This function can be used to manage an application's internal data
    *	memory.  Note that no arbitration of the MemHeader and associated
    *	free chunk list is done.  You must be the owner before calling
    *	Allocate.
    *
    *	This function will allocate accordingly	to your MEMF_#? flags.
    *
    * Params:
    *	byteSize = requested byte size. The size is rounded up to the
    *               next MEM_BLOCKSIZE boundary.
    *	location = Location of absolute chunk to allocate or alignment value
    *	            for aligned allocations ( 0 < x < IPTRBITS ).
    *				E.g. 4k alignment = 2^12 . x = 12
    *	flags = flags to use for allocation
    *
    * Returns:
    *	null on failure, or the pointer to your allocated memory. The memory
    *   is aligned to MEM_BLOCKSIZE boundaries.
    *
    * Notes:
    *	No access abitration is done here. SysBase may be null.
    * See:
    *	initMemList(), addMemHeader(), remMemHeader(), Allocate(), deallocate()
    */
    void* allocateAbs(size_t byteSize, void* location, MemFlags flags) {
        auto alignment = cast(size_t) location;
        void* mymem = null;

        logF(__FUNCTION__ ~ "( %08x,%08x,%08x,%08x )= ", &this, byteSize, location, flags);

        /* First check if there is at least theoretically enough space for
        ** our request. But this does NOT mean, that there is enough continueous
        ** space for our request.
        */
        if (byteSize && this.mh_Free >= byteSize) {
            /* Round up byteSize to next block boundary */
            byteSize = alignValUp(byteSize, MEM_BLOCKEXP);
            if (flags & MemFlags.MEMF_ALIGN) {
                assert(alignment != 0, "Alignment must be > 0");
                assert(alignment < IPTRBITS, "Alignment must be < " ~ text(IPTRBITS));

                alignment = (1 << alignment) - 1;

                if (alignment < MEM_BLOCKMASK) //** Enforce minimum alignment.
                    alignment = MEM_BLOCKMASK;

                location = cast(void*) alignment;
            } else
                location = cast(void*)(cast(size_t) location & ~MEM_BLOCKMASK);

            /*********************************************************************
            ** Now traverse the list to find a memchunk large enough for our
            ** requirements. We can allocate from the front or end of list.
            */
            MemChunk* currmc, newmc;
            if (flags & MemFlags.MEMF_REVERSE)
                currmc = cast(MemChunk*)(this.mh_ChunkList.getTailPred);
            else
                currmc = cast(MemChunk*)(this.mh_ChunkList.getHeadSucc);

            while (currmc.mc_Node.isNodeReal) {
                /* Check if we can fit an aligned block at the start or end of mc */
                if (flags & MemFlags.MEMF_ALIGN) {
                    if (currmc.mc_Bytes >= byteSize) {
                        if (flags & MemFlags.MEMF_REVERSE) {
                            if ((((cast(size_t) currmc + currmc.mc_Bytes - byteSize) & ~alignment) >= cast(size_t) currmc)
                                && (((cast(size_t) currmc + currmc.mc_Bytes - byteSize) & ~alignment) + byteSize
                                    <= cast(
                                    size_t) currmc + currmc.mc_Bytes)
                                )
                                break;
                        } else {
                            if ((((cast(size_t) currmc + alignment) & ~alignment) >= cast(size_t) currmc)
                                && (((cast(size_t) currmc + alignment) & ~alignment) + byteSize
                                    <= cast(
                                    size_t) currmc + currmc.mc_Bytes)
                                )
                                break;
                        }
                    }
                }  /*******************************************************************
                ** absolute allocation
                */
                else {
                    if ((location >= cast(void*) currmc)
                        && (cast(uint) location + byteSize <= cast(uint) currmc + currmc.mc_Bytes)
                        )
                        break;
                }

                if (flags & MemFlags.MEMF_REVERSE)
                    currmc = cast(MemChunk*) currmc.mc_Node.getPrevNode; // Ok, then get previos free node
                else
                    currmc = cast(MemChunk*) currmc.mc_Node.getNextNode; // Ok, then get next free node
            }
            /*********************************************************************
            ** Here at least one mc must be found, or there is no memory chunk
            ** large enough for our request.
            */
            if (currmc.mc_Node.isNodeReal) {
                //** We now precalculate the allocation address.

                if (flags & MemFlags.MEMF_ALIGN) {
                    if (flags & MemFlags.MEMF_REVERSE)
                        mymem = cast(void*)(
                            (cast(size_t) currmc + currmc.mc_Bytes - byteSize) & ~alignment);
                    else
                        mymem = cast(void*)((cast(size_t) currmc + alignment) & ~alignment);
                } else {
                    mymem = location;
                }

                size_t dsz1, dsz2; //** leftover from start and end of memchunk
                dsz1 = cast(size_t) mymem - cast(size_t) currmc; //** new currmc size
                newmc = cast(MemChunk*)(cast(size_t) mymem + byteSize); //** possible new memchunk
                dsz2 = currmc.mc_Bytes - dsz1 - byteSize; //** newmc size

                /**********************************************************************
                ** Ok, now setup the new values.
                */
                if ((cast(void*) currmc == mymem) //** Trivial case
                    && (currmc.mc_Bytes == byteSize)) {
                    mymem = currmc.mc_Node.remNode;
                } else //** Nontrival case
                {
                    if (dsz2) //** Is there a need for a newmc?
                    {
                        newmc.mc_Node = TinyNode();
                        newmc.mc_Bytes = dsz2;
                        this.mh_ChunkList.addNode(newmc.mc_Node, &currmc.mc_Node);
                    }

                    if (dsz1) //** Is the memory left at start
                        currmc.mc_Bytes = dsz1;
                    else
                        currmc.mc_Node.remNode;
                }

                /********************************************************************
                ** Now postprocess the memheader structure amd allocated memory.
                */
                this.mh_Free -= byteSize; // Correct the free size.

                //** Now fulfill some our users additional wishes *******************

                if (flags & MemFlags.MEMF_CLEAR)
                    (cast(ubyte*) mymem)[0 .. alignValUp(byteSize, MEM_BLOCKEXP)] = 0;
                else if (ALLOC_PATTERN)
                    (cast(ulong*) mymem)[0 .. alignValUp(byteSize, MEM_BLOCKEXP) / ulong.sizeof] = FILLPATTERN_ALLOC;
            }
        }

        logFLine("%08x", mymem);
        return mymem;
    }

    /** Allocate aligned memory (2^n)
     *
     * Params:
     *   byteSize = size to allocate
     *   alignment = the 'n' of the 2^n alignment
     *   flags = the MemFlags.
     * Returns:
     *   Adress of allocated memory or null
     */
    void* allocateAligned(size_t byteSize, int alignment, MemFlags flags) {
        flags |= MemFlags.MEMF_ALIGN;
        return allocateAbs(byteSize, cast(void*) alignment, flags);
    }

    /** deallocate -- return memory back to the MemHeader pool
    *
    *	This function deallocates memory by returning it to the appropriate
    *	private free memory pool.  This function can be used to free an
    *	entire block allocated with the above function, or it can be used
    *	to free a sub-block of a previously allocated block.  Sub-blocks
    *	must be an even multiple of the memory chunk size (currently
    *	MEM_BLOCKSIZE bytes). But it's strongly encouraged to deallocate
    *	only blocks as a whole !
    *
    *	This function can even be used to add a new free region to an
    *	existing MemHeader, however the extent pointers in the MemHeader
    *	will no longer be valid. This is strongly discouraged !
    *
    *	If memoryBlock is not on a block boundary (MEM_BLOCKSIZE) then it
    *	will be rounded down in a manner compatible with Allocate().  Note
    *	that this will work correctly with all the memory allocation
    *	functions, but may cause surprises if one is freeing only part of a
    *	region.  The size of the block will be rounded up, so the freed
    *	block will fill to an even memory block boundary.
    *
    * Params:
    *	memoryBlock = address of memory to free
    *	byteSize = size of memory to free.
    *
    * Returns:
    *	The memoryBlock is freed and it's content is no longer valid.
    * See:
    *	initMemList(), addMemHeader(), remMemHeader(), allocate(), allocateAbs()
    */
    void deallocate(void* memoryBlock, size_t byteSize) {
        logFLine(__FUNCTION__ ~ "( %08x,%08x,%08x )", &this, memoryBlock, byteSize);

        if (byteSize &&  //** There must be valid size.
            this.mh_Node.ln_Type == ListNodeType.LNT_MEMORY &&
            memoryBlock >= this.mh_Lower &&  //** Allocated block must be in range of mh
            memoryBlock < this.mh_Upper) {

            assert(((cast(size_t) memoryBlock) & MEM_BLOCKMASK) == 0, "Block must be aligned on right boundary");

            /* Align ptr/size to lower/upper boundary of MEMBLOCKMASK. As memory
            ** of a mh starts a MEM_BLOCKMASK boundary and Allocate will always
            ** will allocate n*MEM_BLOCKSIZE bytes (round up), we must now correct
            ** the byteSize and memoryBlock.
            */
            //** Round down memoryBlock and add difference to byteSize

            size_t tmp = cast(size_t) memoryBlock;
            memoryBlock = cast(MemChunk*) alignValDown(memoryBlock, MEM_BLOCKEXP);
            byteSize += (cast(size_t) memoryBlock - tmp);

            //** Now round byteSize to next boundary
            byteSize = alignValUp(byteSize, MEM_BLOCKEXP);

            /*********************************************************************
            ** Now trace the MemChunk list. We must cover special cases for the
            ** list ends. They stand for mh_Lower/Upper.
            */
            MemChunk* prevmc = cast(MemChunk*) this.mh_Lower; // This is the address of the first possible location
            MemChunk* nextmc = cast(MemChunk*) this.mh_ChunkList.getHeadSucc; // Get Ptr to very first memchunk

            while (!nextmc.mc_Node.isNodeTail) {
                if ((memoryBlock >= cast(void*) prevmc) &&  // FreeMem between those two
                    (memoryBlock < cast(void*) nextmc))
                    break;

                prevmc = nextmc; // Move to next pair of freechunks
                nextmc = cast(MemChunk*) nextmc.mc_Node.getNextNode;
            }
            if (nextmc.mc_Node.isNodeTail)
                nextmc = cast(MemChunk*) this.mh_Upper; // Fake address of a fictious tail node

            /*********************************************************************
            ** Ok, now prevmc is the chunk before our mem, and nextmc is behind
            ** it. We must care about the situation, that prevmc or nextmc are
            ** equal to mh_Lower and mh_Upper.
            **
            ** We can now first do some confidential checks for the operation:
            ** a ) Is the memory to free behind the first chunk.
            ** b ) Does memory overlaps into next chunk ?
            **
            ** psz, qsz contain the size of the prev/next memchunk, or 0 if no exists.
            ** Note: prevmc is mh_Lower, also if a real memchunk exists. So we must
            ** check, if it's the fake value or a real one.
            */
            size_t psz, qsz;

            psz = (cast(void*) prevmc == this.mh_Lower)
                && (cast(void*) this.mh_ChunkList.getHeadSucc != this.mh_Lower) ? size_t(0) : (
                    cast(MemChunk*) prevmc).mc_Bytes;
            qsz = (cast(void*) nextmc == this.mh_Upper) ? size_t(0) : (cast(MemChunk*) nextmc)
                .mc_Bytes;

            assert((cast(size_t) memoryBlock + byteSize) >= (cast(size_t) prevmc + psz), "Inside first chunk.");

            // Check, that the addr range to free is between two MemChunks
            assert(cast(size_t) memoryBlock >= (cast(size_t) prevmc + psz), "Not behind first MemChunk");
            assert(cast(size_t) memoryBlock + byteSize <= cast(size_t) nextmc, "Overlap into next MemChunk!");

            /********************************************************************
            ** Now we know, that we do not overlap other memchunks. Now nuke
            ** out memchunk by adding it as a new memchunk to the free list.
            ** If psz == 0 then prevmc is ListHead. We can pass null to AddNode()
            ** it will use AddNodeHead() then.
            */
            MemChunk* mc = cast(MemChunk*) memoryBlock;
            mc.mc_Bytes = byteSize;

            mc.mc_Node = TinyNode();
            this.mh_ChunkList.addNode(mc.mc_Node, psz ? &prevmc.mc_Node : null); // Put new free chunk to right place

            /********************************************************************
            ** Now we successfully freed our memory. Now the happy merging job
            ** starts. Now there could be following situations:
            **
            ** a ) check if we follow another memchunk. Merge them. Care about
            **	  listhead.
            ** b ) check if we preced another memchunk. Merge them. Care about
            **	   listtail.
            */
            //******** Do we have preceders ???

            if (psz) // Are we not at ListHead ?
            {
                if (cast(size_t) mc == (cast(size_t) prevmc + psz)) // Possible merge with prev mc
                {
                    prevmc.mc_Bytes += mc.mc_Bytes; // Extend previous memchunk

                    mc.mc_Node.remNode; // Remove old mc:
                    mc = cast(MemChunk*) prevmc; // Make this our actual mc.
                }
            }

            //******* Now check, if we are followed directly by another memchunk.

            if (qsz) // Are there followers ?
            {
                if ((cast(size_t) mc) + mc.mc_Bytes == cast(size_t) nextmc) // next free directly follows ?
                {
                    mc.mc_Bytes += nextmc.mc_Bytes; // Extend node and
                    nextmc.mc_Node.remNode; // Remove next free chunk-
                }
            }

            /*********************************************************************
            ** Correct free memory value in MemHeader
            */
            this.mh_Free += byteSize;
        }
    }
}

@("MemHeader: Test FreeList Allocator")
unittest {
    __gshared align(256) ubyte[256] memory;
    auto mh = MemHeader.initMemHeader(memory.length, MemFlags(), 0, memory.ptr, "test memory");
    assert(mh.mh_Attributes == MemFlags.MEMF_ANY);
    assert(mh.mh_Free == 0x80);

    auto maxSize = mh.mh_Free;

    void runTestSetAllocate(MemFlags flags) {
        auto mem1 = mh.allocate(1, flags);
        mh.deallocate(mem1, 1);
        assert(maxSize == mh.mh_Free);

        mem1 = mh.allocate(maxSize, flags);
        mh.deallocate(mem1, maxSize);
        assert(maxSize == mh.mh_Free);

        mem1 = mh.allocate(maxSize / 2, flags);
        auto remainingSize = mh.mh_Free;
        auto mem2 = mh.allocate(mh.mh_Free, flags);
        mh.deallocate(mem1, maxSize / 2);
        mh.deallocate(mem2, remainingSize);
        assert(maxSize == mh.mh_Free);

        TinyHead th;
        th.initListHead;
        while (auto tmp = mh.allocate(TinyNode.sizeof, flags)) {
            auto tn = cast(TinyNode*) tmp;
            *tn = TinyNode();
            tn.addNode(th);
        }
        while (auto tn = th.remNodeHead) {
            mh.deallocate(cast(void*) tn, TinyNode.sizeof);
        }
        assert(maxSize == mh.mh_Free);

        TinyHead th2;
        th2.initListHead;
        while (auto tmp = mh.allocate((th2.isListEmpty ? 2 : 1) * TinyNode.sizeof, flags)) {
            auto tn = cast(TinyNode*) tmp;
            *tn = TinyNode();
            tn.addNode(th);
        }
        while (auto tn = th.remNodeTail) {
            mh.deallocate(cast(void*) tn, (th2.isListEmpty ? 2 : 1) * TinyNode.sizeof);
        }
        assert(maxSize == mh.mh_Free);
    }

    runTestSetAllocate(MemFlags.MEMF_ANY);
    runTestSetAllocate(MemFlags.MEMF_REVERSE);

    runTestSetAllocate(MemFlags.MEMF_ANY | MemFlags.MEMF_CLEAR);
    runTestSetAllocate(MemFlags.MEMF_REVERSE | MemFlags.MEMF_CLEAR);

    void* abTestAddr = mh.mh_Lower + MemHeader.MEM_BLOCKSIZE;

    auto memabs1 = mh.allocateAbs(1, abTestAddr, MemFlags.MEMF_ANY);
    mh.deallocate(memabs1, 1);
    assert(maxSize == mh.mh_Free);

    auto memabs2 = mh.allocateAbs(1 + MemHeader.MEM_BLOCKSIZE, abTestAddr, MemFlags.MEMF_ANY);
    mh.deallocate(memabs2, 1 + MemHeader.MEM_BLOCKSIZE);
    assert(maxSize == mh.mh_Free);

    void runTestSetAllocAligned(MemFlags flags) {
        auto mem1 = mh.allocateAligned(1, 4, flags);
        mh.deallocate(mem1, 1);
        assert(maxSize == mh.mh_Free);

        auto mem2 = mh.allocateAligned(MemHeader.MEM_BLOCKSIZE, 5, flags);
        mh.deallocate(mem2, MemHeader.MEM_BLOCKSIZE);
        assert(maxSize == mh.mh_Free);
    }

    runTestSetAllocAligned(MemFlags.MEMF_ALIGN);
    runTestSetAllocAligned(MemFlags.MEMF_ALIGN | MemFlags.MEMF_REVERSE);

    runTestSetAllocAligned(MemFlags.MEMF_ALIGN | MemFlags.MEMF_CLEAR);
    runTestSetAllocAligned(MemFlags.MEMF_ALIGN | MemFlags.MEMF_REVERSE | MemFlags.MEMF_CLEAR);
}

@("MemHeader: Test Random Alloc Any/Reverse/Clear")
unittest {
    import std.random : Random, uniform;

    const size_t testSize = 1024 * 1024;
    __gshared align(2 ^^ MemHeader.MEM_BLOCKEXP) ubyte[testSize] memory;
    auto mh = MemHeader.initMemHeader(memory.length, MemFlags(), 0, memory.ptr, "test memory");

    TinyHead th;
    th.initListHead;
    auto rnd = Random(0x4362897);
    size_t getRSz() {
        return uniform(1, 1024, rnd);
    }

    MemHeader.MemChunk* makeNode(size_t sz, MemFlags flags) {
        auto mc = cast(MemHeader.MemChunk*) mh.allocate(sz, flags);
        if (mc) {
            mc.mc_Node = TinyNode();
            mc.mc_Bytes = sz;
        }
        return mc;
    }

    foreach (loop; 1 .. 100) {
        logFLine("Allocate....");
        while (mh.mh_Free >= (1 * mh.mh_Total / 4)) // fill up to 25%
        {
            auto sz = getRSz();
            MemFlags flags = sz & 1 ? MemFlags.MEMF_REVERSE : MemFlags.MEMF_ANY;
            auto mc = makeNode(sz, flags);
            if (mc)
                mc.mc_Node.addNode(th);
            else
                break;
        }
        logFLine("Deallocate....");
        while (mh.mh_Free < (3 * mh.mh_Total / 4)) {
            auto mc = cast(MemHeader.MemChunk*) th.remNodeTail;
            if (mc)
                mh.deallocate(cast(void*) mc, mc.mc_Bytes);
        }
    }
    logFLine("Deallocate all....");

    while (auto tn = cast(MemHeader.MemChunk*) th.remNodeTail) {
        mh.deallocate(cast(void*) tn, tn.mc_Bytes);
    }
    assert(mh.mh_Total == mh.mh_Free);
}

@("MemHeader: Test Random AllocAlign Any/Reverse/Clear")
unittest {
    // DEBUG=true;
    import std.random : Random, uniform;

    const size_t testSize = 1024 * 1024;
    __gshared align(1024) ubyte[testSize] memory;
    auto mh = MemHeader.initMemHeader(memory.length, MemFlags(), 0, memory.ptr, "test memory");

    TinyHead th;
    th.initListHead;
    auto rnd = Random(0x4362897);
    size_t getRSz() {
        return uniform(1, 1024, rnd);
    }

    MemHeader.MemChunk* makeNode(size_t sz, MemFlags flags) {
        auto mc = cast(MemHeader.MemChunk*) mh.allocateAligned(sz, 10, flags);
        assert((cast(size_t) mc & 2 ^^ 10 - 1) == 0, "Wrong alignment");
        if (mc) {
            mc.mc_Node = TinyNode();
            mc.mc_Bytes = sz;
        }
        return mc;
    }

    foreach (loop; 1 .. 100) {
        logFLine("Allocate....");
        while (mh.mh_Free >= (1 * mh.mh_Total / 4)) // fill up to 25%
        {
            auto sz = getRSz();
            MemFlags flags = sz & 1 ? MemFlags.MEMF_REVERSE : MemFlags.MEMF_ANY;
            auto mc = makeNode(sz, flags);
            if (mc)
                mc.mc_Node.addNode(th);
            else
                break;
        }
        logFLine("Deallocate....");
        while (mh.mh_Free < (3 * mh.mh_Total / 4)) {
            auto mc = cast(MemHeader.MemChunk*) th.remNodeTail;
            if (mc)
                mh.deallocate(cast(void*) mc, mc.mc_Bytes);
        }
    }
    logFLine("Deallocate all....");

    while (auto tn = cast(MemHeader.MemChunk*) th.remNodeTail) {
        mh.deallocate(cast(void*) tn, tn.mc_Bytes);
    }
    assert(mh.mh_Total == mh.mh_Free);
}

/** Memory Subsystem
 *
 * This class implements the API
 *
 */
class Memory {

    ListHead sys_MemHeaders; // Memory Management
    Mutex sys_MemHeadersSema;

    ListHead sys_MemHandlers; // The memory handler list
    MemHandler* sys_MemHandler;

    this() {
        sys_MemHeadersSema = new Mutex;
        sys_MemHeaders.initListHead;
        sys_MemHandlers.initListHead;
    }

    private void obtainSemaphore(ref Mutex mutex, bool read) {
        mutex.lock_nothrow();
    }

    private void releaseSemaphore(ref Mutex mutex) {
        mutex.unlock_nothrow();
    }

    /** addMemHeader -- Add system memory to public memory lists
    *
    *	This function adds the given memory range to the system management.
    *	The given memory must be large enough to keep the MemHeader
    *	and a MemChunk node. The first few bytes will be used to hold the
    *	MemHeader structure.  The remainder	will be made available to the
    *	rest of the world.
    *
    * Params:
    *	size = size of memory range to add
    *	attributes = memory attributes to associate with memory range
    *	pri = ln_Priority for this memory range
    *	membase = base address of memory to add
    *	name = a symbolic name for this memory range
    *
    * Returns:
    *	Memory range is added to system memory management
    * See:
    *	initMemList(), remMemHeader(), Allocate(), deallocate()
    */
    MemHeader* addMemHeader(const size_t size, MemFlags attributes, short pri, void* membase, string name) {
        logFLine(__FUNCTION__ ~ "( %08x,%08x,%08x,%08x,%s )", size, attributes, pri, membase, name);

        MemHeader* mhp = MemHeader.initMemHeader(size, attributes, pri, membase, name);
        obtainSemaphore(this.sys_MemHeadersSema, false);
        addNodeSorted(&this.sys_MemHeaders, mhp.mh_Node);
        releaseSemaphore(this.sys_MemHeadersSema);
        return mhp;
    }

    /** remMemHeader -- Remove a memory range from system management
    *
    *	Remove a memory range from public list, if there is no allocated memory
    *	associated with this MemHeader any more.
    *
    * Params:
    *	memheader = Pointer to remove from list
    *
    * Returns:
    *	Either pointer to removed MemHeader or null, if MemHeader can't be
    *   removed.
    *
    * See:
    *	initMemList(), addMemHeader(), Allocate(), deallocate()
    */
    MemHeader* remMemHeader(MemHeader* memheader)
    in (memheader !is null, "Missing pointer")
    in (memheader.mh_Node.ln_Type == ListNodeType.LNT_MEMORY, "Wrong type") {
        MemHeader* mhp = null;
        logFLine(__FUNCTION__ ~ "( %08x )", memheader);

        /* Remove node from public list, if entirely empty. */
        if (memheader.mh_Free == memheader.mh_Total)
            mhp = cast(MemHeader*) memheader.mh_Node.remNode;

        return mhp;
    }

    /** AddMemHandler -- add a MemHandler to system list
    *
    *	This function adds a low memory handler to the system.  The handler
    *	is described in the Interrupt structure.  Due to multitasking
    *	issues, the handler must be ready to run the moment this function
    *	call is made.  (The handler may be called before the call returns)
    *
    * Params:
    *	name = Name of handler
    *   pri = priority of handler
    *   usercode = function pointer to handler
    *   userdata = some pointer to be passed to handler later
    *
    * Returns:
    *	MemHandler - Pointer to installed MemHandler or null.
    *
    * Notes:
    *	Adding a handler from within a handler will cause undefined
    *	actions.  It is safe to add a handler to the list while within
    *	a handler but the newly added handler may or may not be called
    *	for the specific failure currently running.
    * See:
    *	RemMemHandler
    */
    MemHandler* addMemHandler(string name, short pri, MEMHANDLERCODE usercode, void* userdata)
    in (usercode !is null, "Needs a pointer to the lowmem handler.")
    do {
        logFLine(__FUNCTION__ ~ "( %s, %08x,%08x,%08x )", name, pri, usercode, userdata);

        auto memHandler =
            cast(MemHandler*)
            allocMem(MemHandler.sizeof, MemFlags.MEMF_PUBLIC | MemFlags.MEMF_CLEAR);

        if (memHandler) {
            memHandler.mmh_Node = ListNode(null, null, ListNodeType.LNT_MEMHANDLER, pri, name);

            memHandler.mmh_UserCode = usercode;
            memHandler.mmh_UserData = userdata;

            obtainSemaphore(this.sys_MemHeadersSema, false);
            addNodeSorted(&this.sys_MemHandlers, memHandler.mmh_Node);
            releaseSemaphore(this.sys_MemHeadersSema);
        }
        return memHandler;
    }

    /** RemMemHandler -- remove a MemHandler from system list
    *
    *	This function removes the low memory handler from the system.
    *	This function can be called from within a handler.  If removing
    *	oneself, it is important that the handler returns MEM_ALL_DONE.
    *
    * Params:
    *	memHandler = Pointer to a handler added with AddMemHandler()
    *
    * Returns:
    *	none
    *
    * Notes:
    *	When removing a handler, the handler may be called until this
    *	function returns.  Thus, the handler must still be valid until
    *	then.
    *
    * See:
    *	AddMemHandler()
    */
    void remMemHandler(MemHandler* memHandler)
    in (memHandler !is null, __FUNCTION__ ~ ": Missing ptr.")
    in (memHandler.mmh_Node.ln_Type == ListNodeType.LNT_MEMHANDLER, __FUNCTION__ ~ ": Wrong type.")
    do {
        logFLine(__FUNCTION__ ~ "( %08x )\n", memHandler);

        obtainSemaphore(this.sys_MemHeadersSema, false);
        memHandler.mmh_Node.remNode();
        releaseSemaphore(this.sys_MemHeadersSema);

        freeMem(memHandler, MemHandler.sizeof);
    }

    /** CallMemHandlers -- Call MemHandlers to free memory.
    *
    *	Call MemHandlers in system list, until enough memory is available for
    *	pending Allocate#?() operation, or until no more memory can be freed
    *	by MemHandlers.
    *   Note: Code is called with Memory Semaphore locked exclusively. So do
    *	never Wait() in your Handler !
    *
    * Params:
    *	byteSize = number of bytes needed for pending allocations
    *   alignment = current alignment value, or 0 for any.
    *	flags = allocation flags required for pending allocation
    *
    * Returns:
    *	Return code from the handler called.
    *
    * Notes:
    *	Remember to set sys_MemHandler to null, if AllocMem() is called.
    *	This will reset the current handler ptr.
    *
    * See:
    *	AddMemHandler(), RemMemHandler()
    */
    STATUS callMemHandlers(size_t byteSize, uint alignment, uint flags)
    in (byteSize, "byteSize must be > 0")
    do {
        logFLine(__FUNCTION__ ~ "( %08x,%08x )\n", byteSize, flags);

        STATUS rc = MEM_ALL_DONE;
        do {
            MemHandler* mmh = null;

            /* First check, if we must reload the "working" ptr. Otherwise check
            ** if we must go to next node or not. Last check for list tail.
            */
            if (!this.sys_MemHandlers.isListEmpty) {
                //**--- Restart chain if sys_MemHandler is null
                if (this.sys_MemHandler == null) {
                    mmh = cast(MemHandler*) this.sys_MemHandlers.getHeadSucc;
                    this.sys_MemHandler = mmh;
                    mmh.mmh_Flags = 0;
                }  //**--- Check, if we must advance to next node, or retry
                else {
                    mmh = this.sys_MemHandler;

                    if (!(mmh.mmh_Flags & MEMHF_RECYCLE)) {
                        mmh = cast(MemHandler*) mmh.mmh_Node.getNextNode();
                        if (mmh.mmh_Node.isNodeTail)
                            mmh = null;
                        this.sys_MemHandler = mmh;
                    }
                }
            } else
                this.sys_MemHandler = mmh = null;

            /*********************************************************************
            ** Check, if we have a memhandler found. If, execute it.
            ** If return value us MEM_TRY_AGAIN, remember to retry this handler
            ** next time again. (MEMHF_RECYCLE)
            */
            if (mmh) {
                //**---- Fill in the MemHandlerData structure. mhd_Flags
                //**---- tells the handler if this is a retry
                MemHandlerData mhd;
                mhd.mhd_RequestSize = byteSize;
                mhd.mhd_RequestAlign = alignment;
                mhd.mhd_RequestFlags = flags;
                mhd.mhd_Flags = mmh.mmh_Flags;

                logFLine("Call MemHandler '%s'\n", mmh.mmh_Node.ln_Name);

                rc = mmh.mmh_UserCode(this, mmh, &mhd);

                //**---- Check if this handler can be called again.
                if (rc == MEM_TRY_AGAIN)
                    mmh.mmh_Flags |= MEMHF_RECYCLE; // Remember to call again
                else
                    mmh.mmh_Flags &= ~MEMHF_RECYCLE; // Do not retry this one
            } else
                rc = MEM_ALL_DONE;

            /*********************************************************************
                ** Reiterate until we reached end of list, or got some memory.
                */
        }
        while (rc == MEM_DID_NOTHING);
        return rc;
    }

    /** SystemMemHandler -- Internal System MemHandler.
    *
    *	Tries to expunge some libs and devices.
    *
    * Params:
    *   memory = Pointer to Memory
    *	mmh = Pointer to MemHandler
    *	mhd = Pointer to MemHandlerData, allocation flags required for pending allocation
    *
    * Returns:
    *	A MemHandler return value.
    *
    * Example:
    *	none
    *
    * Notes:
    *	Remember to set sys_MemHandler to null, if AllocMem() is called.
    *	This will reset the current handler ptr.
    *
    * See:
    *	AddMemHandler(), RemMemHandler(), CallMemHandlers()
    */
    static STATUS systemMemHandler(Memory memory, MemHandler* mmh, MemHandlerData* mhd) {
        logFLine("SysMemHandler called(%s, %x) = MEM_DID_NOTHING");

        //FIXME: Implement SysMemHandler.
        return MEM_DID_NOTHING; // FIXME: Expunge libs.
    }

    /** AllocMem -- Allocate memory
    *
    * SYNOPSIS
    *	void* AllocMem( Memory* SysBase, uint byteSize, uint requirements );
    *
    * FUNCTION
    *	This is the memory allocator to be used by system code and
    *	applications.  It provides a means of specifying that the allocation
    *	should be made in a memory area accessible to the chips, or
    *	accessible to shared system code.
    *
    *	Memory is allocated based on requirements and options.	Any
    *	"requirement" must be met by a memory allocation, any "option" will
    *	be applied to the block regardless.  AllocMem will try all memory
    *	spaces until one is found with the proper requirements and room for
    *	the memory request.
    *
    * Params:
    *	byteSize = the size of the desired block in bytes.  (The operating
    *		system will automatically round this number to a multiple of
    *		the system memory chunk size (MEM_BLOCKSIZE) )
    *
    *	requirements =
    *	  requirements
    *		If no flags are set (MEMF_ANY), the system will return the best
    *		available memory block.  For expanded systems, the fast
    *		memory pool is searched first.
    *
    *		MEMF_PUBLIC:	Memory that must not be mapped, swapped,
    *				or otherwise made non-addressable. ALL
    *				MEMORY THAT IS REFERENCED VIA INTERRUPTS
    *				AND/OR BY OTHER TASKS MUST BE EITHER PUBLIC
    *				OR LOCKED INTO MEMORY! This includes both
    *				code and data.
    *		MEMF_FAST:	This is cpu-local memory.  If no flag is set
    *				MEMF_FAST is taken as the default.
    *
    *				DO NOT SPECIFY MEMF_FAST unless you know
    *				exactly what you are doing!  If MEMF_FAST is
    *				set, AllocMem() will fail on machines that
    *				only have chip memory!  This flag may not
    *				be set when MEMF_CHIP is set.
    *		MEMF_VIDEO:	This is video memory.  Some graphics chips
    *	            allow to use the graphics mem like usual memory.
    *				Useful for allocating BitMaps etc.
    *		MEMF_VIRTUAL:	This is mapped memory.  This flag requests
    *	            memory, that can be swapped out to HD, if your
    *	            system cpu that. MMU required. Other allocation will
    *	            fail.
    *		MEMF_PERMANENT:	This is memory that will not go away
    *				after the CPU RESET instruction.  Normally,
    *				autoconfig memory boards become unavailable
    *				after RESET while motherboard memory
    *				may still be available.
    *	  options
    *		MEMF_CLEAR:	The memory will be initialized to all
    *				zeros.
    *		MEMF_REVERSE:	This allocates memory from the top of
    *				the memory pool.  It searches the pools
    *				in the same order, such that FAST memory
    *				will be found first.  However, the
    *				memory will be allocated from the highest
    *				address available in the pool.
    *		MemFlags.MEMF_NO_EXPUNGE	This will prevent an expunge to happen on
    *				a failed memory allocation.  If a memory allocation
    *				with this flag set fails, the allocator will not cause
    *				any expunge operations.  (See AddMemHandler())
    *
    * Result:
    *	memoryBlock - a pointer to the newly allocated memory block.
    *		If there are no free memory regions large enough to satisfy
    *		the request, zero will be returned.  The pointer must be
    *		checked for zero before the memory block may be used!
    *		The memory block returned is long word aligned.
    *
    * Warning:
    *	The result of any memory allocation MUST be checked, and a viable
    *	error handling path taken.  ANY allocation may fail if memory has
    *	been filled.
    *
    * Example:
    *	AllocMem(64,0L)		- Allocate the best available memory
    *	AllocMem(25,MEMF_CLEAR) - Allocate the best available memory, and
    *				  clear it before returning.
    *	AllocMem(128,MEMF_FAST) - Allocate cpu-local memory
    *	AllocMem(128,MEMF_VIDEO|MEMF_CLEAR) - Allocate cleared gfx memory
    *	AllocMem(821,MEMF_FAST|MEMF_PUBLIC|MEMF_CLEAR) - Allocate cleared,
    *		public, cpu-local memory.
    *
    * Note:
    *	If the free list is corrupt, the system will panic with alert
    *	SEN_MemCorrupt.
    *
    *	This function may not be called from interrupts.
    * See:
    *	FreeMem()
    */
    void* allocMem(size_t byteSize, MemFlags requirements)
    in (byteSize, "Can't allocate a 0 byte quantity")
    do {
        STATUS stat = MEM_ALL_DONE;
        void* mptr = null;
        logFLine(__FUNCTION__ ~ "( %08x,%08x )", byteSize, requirements);

        //**-- Bounds checking requires at least one cacheline ----------------
        if (BOUNDS_CHECKING)
            byteSize += getMungwallExtraSize(0);

        //**-- Get the list of ------------------------------------------------
        obtainSemaphore(this.sys_MemHeadersSema, false);
        this.sys_MemHandler = null; // Reset handler chain

        //**-- Traverse MemHeaders of right type, and try to get memory. ------
        do {
            auto mh = cast(MemHeader*) sys_MemHeaders.getHeadSucc();
            while (!mh.mh_Node.isNodeTail) {
                if (((mh.mh_Attributes & requirements) & MemFlags.MEMF_MASKFLAGS) == (
                        requirements & MemFlags.MEMF_MASKFLAGS)) {
                    if (mh.mh_Free >= byteSize) {
                        mptr = mh.allocate(byteSize, requirements);
                        if (mptr)
                            break;
                    }
                }
                mh = cast(MemHeader*) mh.mh_Node.getNextNode;
            }
            //**-- Try to free some memory and retry, if we got some memory back.

            if ((mptr == null) && !(requirements & MemFlags.MEMF_NO_EXPUNGE))
                stat = callMemHandlers(byteSize, 0, requirements);
        }
        while (((!mptr) && (stat != MEM_ALL_DONE)));

        //-- Now we apply some cheap bounds checking for our code ------------------
        if (BOUNDS_CHECKING && mptr)
            mptr = setupMungwall(mptr, byteSize);

        releaseSemaphore(this.sys_MemHeadersSema);

        return mptr;
    }

    /** allocAbs -- Allocate absolute memory
    *
    *	This function attempts to allocate memory at a given absolute
    *	memory location.  Often this is used by boot-surviving entities
    *	such as recoverable ram-disks.	If the memory is already being
    *	used, or if there is not enough memory to satisfy the request,
    *	AllocAbs will return null.
    *
    *	This block may not be exactly the same as the requested block
    *	because of rounding, but if the return value is non-zero, the block
    *	is guaranteed to contain the requested range.
    *
    * Params:
    *	byteSize = the size of the desired block in bytes
    *		   This number is rounded up to the next larger
    *		   block size for the actual allocation.
    *
    *	location = the address where the memory MUST be.
    *
    *   flags =
    *		(see. AllocMem() for flags.)
    *
    * Returns:
    *	memoryBlock - a pointer to the newly allocated memory block, or
    *		      null if failed.
    * Notes:
    *	If the free list is corrupt, the system will panic with alert
    *	SEN_MemCorrupt.
    *
    *	The MEM_BLOCKSIZE bytes past the end of an AllocAbs will be changed while
    *	relinking the next block of memory.  Generally you can't trust
    *	the first MEM_BLOCKSIZE bytes of anything you AllocAbs().
    *
    * See:
    *	AllocMem(), AllocAlign()
    */
    void* allocAbs(size_t byteSize, void* location, MemFlags flags)
    in (byteSize, "Mustbe >0 bytes")
    in (!(flags & MemFlags.MEMF_ALIGN), "ALIGN flag is set?")
    do {
        MemHeader* mh;
        void* mptr = null;
        logFLine(__FUNCTION__ ~ "( %08x,%08x,%08x )\n", byteSize, location, flags);

        if (BOUNDS_CHECKING) {
            byteSize += getMungwallExtraSize(0);
            location = location - MemHeader.MEM_BLOCKSIZE;
        }

        obtainSemaphore(this.sys_MemHeadersSema, false);
        mh = cast(MemHeader*) this.sys_MemHeaders.getHeadSucc;
        while (!mh.mh_Node.isNodeTail) {
            if ((mh.mh_Free >= byteSize)
                && (location >= mh.mh_Lower)
                && ((cast(size_t) location + byteSize) <= cast(size_t) mh.mh_Upper)
                ) {
                mptr = mh.allocateAbs(byteSize, location, flags);
                break;
            }
            mh = cast(MemHeader*) mh.mh_Node.getNextNode;
        }

        if (BOUNDS_CHECKING && mptr)
            mptr = setupMungwall(mptr, byteSize);

        releaseSemaphore(this.sys_MemHeadersSema);
        return mptr;
    }

    /** allocAlign -- Allocate aligned memory
    *
    *	This function attempts to allocate memory at an aligned
    *	memory location.  Often this is used by memory mappers (vmem).
    *	If there is not enough memory to satisfy the request,
    *	AllocAlign() will return null.
    *
    * Params:
    *	byteSize = the size of the desired block in bytes
    *		   This number is rounded up to the next larger
    *		   block size for the actual allocation.
    *
    *	alignment = the n value where the memory MUST be aligned to.
    *		   ( 2^n memory boundary..)
    *
    *   flags = (see. AllocMem() for flags.)
    *
    * Returns:
    *	memoryBlock - a pointer to the newly allocated memory block, or
    *		      null if failed.
    *
    * Notes:
    *	If the free list is corrupt, the system will panic with alert
    *	SEN_MemCorrupt.
    *
    *	The 8 bytes past the end of an AllocAbs will be changed by Exec
    *	relinking the next block of memory.  Generally you can't trust
    *	the first MEM_BLOCKSIZE bytes of anything you AllocAbs().
    *
    * Bugs:
    *	none
    *
    * See:
    *	AllocMem(), AllocAbs()
    */
    void* allocAlign(size_t byteSize, uint alignment, MemFlags flags)
    in (byteSize, __FUNCTION__ ~ ": byteSize must be >0")
    do {
        logFLine(__FUNCTION__ ~ "( %08x,%08x,%08x )", byteSize, alignment, flags);

        if (BOUNDS_CHECKING)
            byteSize += getMungwallExtraSize(alignment);

        obtainSemaphore(this.sys_MemHeadersSema, false);
        this.sys_MemHandler = null; // Reset handler chain

        //**-- Traverse MemHeaders of right type, and try to get memory.
        void* mptr = null;
        STATUS stat = MEM_ALL_DONE;
        do {
            auto mh = cast(MemHeader*) this.sys_MemHeaders.getHeadSucc;
            while (!mh.mh_Node.isNodeTail) {
                if (((mh.mh_Attributes & flags) & MemFlags.MEMF_MASKFLAGS)
                    == (
                        flags & MemFlags.MEMF_MASKFLAGS)) {
                    if (mh.mh_Free >= byteSize) {
                        mptr = mh.allocateAligned(byteSize, alignment, MemFlags.MEMF_ALIGN | flags);
                        if (mptr)
                            break;
                    }
                }
                mh = cast(MemHeader*) mh.mh_Node.getNextNode;
            }
            //**-- Try to free some memory and retry, if we got some memory back.
            if ((mptr == null) && !(flags & MemFlags.MEMF_NO_EXPUNGE))
                stat = callMemHandlers(byteSize, alignment, flags);

        }
        while (((!mptr) && (stat != MEM_ALL_DONE)));

        if (BOUNDS_CHECKING && mptr)
            mptr = setupMungwall(mptr, byteSize, alignment);

        releaseSemaphore(this.sys_MemHeadersSema);

        return mptr;
    }

    /** freeMem -- Free byteSize byte sof memory at memoryBlock.
    *
    *	Free a region of memory, returning it to the system pool from which
    *	it came.  Freeing partial blocks back into the system pool is
    *	unwise.
    *
    * Params:
    *	memoryBlock = pointer to the memory block to free
    *	byteSize = the size of the desired block in bytes.  (The operating
    *		system will automatically round this number to a multiple of
    *		the system memory chunk size)
    *
    * Returns:
    *	none
    *
    * Notes:
    *	If a block of memory is freed twice, the system will Guru. The
    *	Alert is SEN_FreeTwice.   If you pass the wrong pointer,
    *	you will probably see SEN_MemCorrupt.  Future versions may
    *	add more sanity checks to the memory lists.
    *
    * See:
    *	AllocMem(), AllocAbs(), AllocAligned()
    */
    void freeMem(void* memoryBlock, size_t byteSize)
    in (memoryBlock !is null, __FUNCTION__ ~ ": Need ptr to blk.")
    in (byteSize, __FUNCTION__ ~ ": size must be >0")
    do {
        logFLine(__FUNCTION__ ~ "( %08x,%08x )", memoryBlock, byteSize);

        obtainSemaphore(this.sys_MemHeadersSema, false);
        MemHeader* mhp = cast(MemHeader*) this.sys_MemHeaders.getHeadSucc;
        while (!mhp.mh_Node.isNodeTail) {
            if (memoryBlock >= mhp.mh_Lower &&
                memoryBlock < mhp.mh_Upper) {
                if (BOUNDS_CHECKING) {
                    checkMungwall(memoryBlock, byteSize);
                    // After this point memoryBlock and byteSize are restored to original values.
                }
                mhp.deallocate(memoryBlock, byteSize);
                releaseSemaphore(this.sys_MemHeadersSema);
                return;
            }
            mhp = cast(MemHeader*) mhp.mh_Node.getNextNode;
        }
        releaseSemaphore(this.sys_MemHeadersSema);
        assert(false, __FUNCTION__ ~ ": Bad free address.");
    }

    /** allocVec -- Allocate vectored memory.
    *
    *	This function works identically to AllocMem(), but tracks the size
    *	of the allocation.
    *
    *	See the AllocMem() documentation for details.
    *
    * Params:
    *	byteSize = the size of the desired block in bytes.  (The operating
    *		system will automatically round this number to a multiple of
    *		the system memory chunk size (MEM_BLOCKSIZE) )
    *
    *	requirements =
    *	  requirements
    *		If no flags are set (MEMF_ANY), the system will return the best
    *		available memory block.  For expanded systems, the fast
    *		memory pool is searched first.
    *
    *		MEMF_PUBLIC:	Memory that must not be mapped, swapped,
    *				or otherwise made non-addressable. ALL
    *				MEMORY THAT IS REFERENCED VIA INTERRUPTS
    *				AND/OR BY OTHER TASKS MUST BE EITHER PUBLIC
    *				OR LOCKED INTO MEMORY! This includes both
    *				code and data.
    *		MEMF_FAST:	This is cpu-local memory.  If no flag is set
    *				MEMF_FAST is taken as the default.
    *
    *				DO NOT SPECIFY MEMF_FAST unless you know
    *				exactly what you are doing!  If MEMF_FAST is
    *				set, AllocMem() will fail on machines that
    *				only have chip memory!  This flag may not
    *				be set when MEMF_CHIP is set.
    *		MEMF_VIDEO:	This is video memory.  Some graphics chips
    *	            allow to use the graphics mem like usual memory.
    *				Useful for allocating BitMaps etc.
    *		MEMF_VIRTUAL:	This is mapped memory.  This flag requests
    *	            memory, that can be swapped out to HD, if your
    *	            system cpu that. MMU required. Other allocation will
    *	            fail.
    *		MEMF_PERMANENT:	This is memory that will not go away
    *				after the CPU RESET instruction.  Normally,
    *				autoconfig memory boards become unavailable
    *				after RESET while motherboard memory
    *				may still be available.
    *	  options
    *		MEMF_CLEAR:	The memory will be initialized to all
    *				zeros.
    *		MEMF_REVERSE:	This allocates memory from the top of
    *				the memory pool.  It searches the pools
    *				in the same order, such that FAST memory
    *				will be found first.  However, the
    *				memory will be allocated from the highest
    *				address available in the pool.
    *		MemFlags.MEMF_NO_EXPUNGE	This will prevent an expunge to happen on
    *				a failed memory allocation.  If a memory allocation
    *				with this flag set fails, the allocator will not cause
    *				any expunge operations.  (See AddMemHandler())
    *
    * Returns:
    *	See the AllocMem() documentation for details.
    *
    * Example:
    *	See the AllocMem() documentation for details.
    *
    * Notes:
    *	See the AllocMem() documentation for details.
    *
    * See:
    *	FreeVec(), AllocMem()
    */
    void* allocVec(size_t byteSize, MemFlags requirements) {
        size_t* mem;
        logFLine(__FUNCTION__ ~ "( %08x,%08x )", byteSize, requirements);

        mem = cast(size_t*) allocMem(byteSize + size_t.sizeof, requirements);
        if (mem) {
            *mem++ = byteSize + size_t.sizeof;
        }
        return mem;
    }

    /** freeVec -- Free vectored memory
    *
    *	Free an allocation made by the AllocVec() call.  The memory will
    *	be returned to the system pool from which it came.
    *
    * Params:
    *	memoryBlock = block to free. Must be allocated with AllocVec()
    *
    * Returns:
    *	none
    *
    * Notes:
    *	If a block of memory is freed twice, the system will Guru. The
    *	Alert is SEN_FreeTwice.   If you pass the wrong pointer,
    *	you will probably see SEN_MemCorrupt.  Future versions may
    *	add more sanity checks to the memory lists.
    *
    * See:
    *	AllocVec()
    */
    void freeVec(void* memoryBlock) {
        if (memoryBlock) {
            size_t* mem = cast(size_t*) memoryBlock;
            logFLine(__FUNCTION__ ~ "( %08x )", memoryBlock);
            freeMem(mem - 1, *(mem - 1));
        }
    }

    /** AvailMem -- Get number of free bytes for given attributes
    *
    *	This function returns the amount of free memory given certain
    *	attributes.
    *
    *	To find out what the largest block of a particular type is, add
    *	MEMF_LARGEST into the requirements argument.  Returning the largest
    *	block is a slow operation.
    *
    *   Warning:
    *	Due to the effect of multitasking, the value returned may not
    *	actually be the amount of free memory available at that instant.
    *
    * Params:
    *	requirements = a requirements mask as specified in AllocMem.  Any
    *		       of the AllocMem bits are valid, as is MEMF_LARGEST
    *		       which returns the size of the largest block matching
    *		       the requirements.
    *
    * Returns:
    *	size - total free space remaining (or the largest free block).
    *
    * Example:
    *	AvailMem(MEMF_ANY|MEMF_LARGEST);
    *	\* return size of largest available memory chunk *\
    *
    * Notes:
    *	AvailMem(MEMF_LARGEST) does a consistency check on the memory list.
    *   SysError SEN_MemoryInsane will be pulled if any mismatch is noted.
    *
    * See:
    *	AllocMem()
    */
    size_t availMem(MemFlags requirements) {
        MemHeader* mh = cast(MemHeader*) this.sys_MemHeaders.getHeadSucc;
        MemHeader.MemChunk* mc;
        size_t rc = 0;
        logF(__FUNCTION__ ~ "( %s )=", requirements);

        obtainSemaphore(this.sys_MemHeadersSema, false);
        while (!mh.mh_Node.isNodeTail) {
            bool matchedAttrs =
                ((mh.mh_Attributes & requirements) & MemFlags.MEMF_MASKFLAGS) ==
                (requirements & MemFlags.MEMF_MASKFLAGS);
            if (matchedAttrs) {
                if (requirements & MemFlags.MEMF_LARGEST) {
                    mc = cast(MemHeader.MemChunk*) mh.mh_ChunkList.getHeadSucc;
                    size_t total = 0;
                    while (!mc.mc_Node.isNodeTail) {
                        rc = (rc < mc.mc_Bytes) ? mc.mc_Bytes : rc;
                        total += mc.mc_Bytes;

                        /* We do nasty things here - we force clean the contents of the
                        * free memory chunk list. */
                        if (DEALLOC_PATTERN) {
                            memset(mc + 1, cast(ubyte) FILLPATTERN_FREE,
                                mc.mc_Bytes - MemHeader.MemChunk.sizeof);
                        }

                        mc = cast(MemHeader.MemChunk*) mc.mc_Node.getNextNode;
                    }
                    assert(total == mh.mh_Free, "SEN_MemInsane");
                }  //
                else if (requirements & MemFlags.MEMF_TOTAL) {
                    rc += cast(size_t) mh.mh_Total;
                }  //
                else
                    rc += mh.mh_Free;

            }
            /++
                mc = (MemChunk*)GetNextNode(&mh.mh_ChunkList);
                while ( !IsNodeTail(mc) )
                {
                    CLib_MemSet( mc+1, FILLPATTERN_FREE, mc.mc_Bytes-sizeof(MemChunk) );     // Debugging aid.
                    mc = (MemChunk*)GetNextNode(mc);
                }
            ++/
            mh = cast(MemHeader*) mh.mh_Node.getNextNode;
        }
        releaseSemaphore(this.sys_MemHeadersSema);

        logFLine("%08x", rc);
        return rc;
    }

    /*** TypeOfMem -- Query attributes of memory address
    *
    *	Given a RAM memory address, search the system memory lists and
    *	return its memory attributes.  The memory attributes are similar to
    *	those specified when the memory was first allocated: (eg. MEMF_VIDEO
    *	and MEMF_FAST).
    *
    *	If the address is not in known-space, a zero will be returned.
    *	(Anything that is not RAM, like the ROM or expansion area, will
    *	return zero.  Also the first few bytes of a memory area are used up
    *	by the MemHeader.)
    *
    * INPUT
    *	address - a memory address
    *
    * Returns:
    *	attributes - a long word of memory attribute flags.
    *	If the address is not in known RAM, zero is returned.
    *
    * See:
    *	AllocMem()
    */
    MemFlags typeOfMem(void* address) {
        MemFlags rc = MemFlags.MEMF_ANY;
        logF(__FUNCTION__ ~ "( %08x ) = ", address);

        obtainSemaphore(this.sys_MemHeadersSema, false);
        auto mh = cast(MemHeader*) this.sys_MemHeaders.getHeadSucc;
        while (!mh.mh_Node.isNodeTail) {
            if (address >= mh.mh_Lower &&
                address < mh.mh_Upper) {
                rc = mh.mh_Attributes;
                break;
            }
            mh = cast(MemHeader*) mh.mh_Node.getNextNode;
        }
        releaseSemaphore(this.sys_MemHeadersSema);
        logFLine("%08x", rc);
        return rc;
    }

    /** MemEntries
    *
    * Note: sizeof(struct MemEntries) includes the size of the first MemEntry!
    */
    struct MemEntries {
        ListNode ml_Node;
        uint ml_NumEntries = 1; // number of entries in this struct
        MemEntry[1] ml_ME; // the first entry

        /** MemEntry */
        struct MemEntry {
            union {
                MemFlags mea_Reqs; // the AllocMem requirements
                void* mea_Addr; // the address of this memory region
            }

            size_t me_Length; // the length of this memory region

            this(MemFlags flags, size_t sz) {
                mea_Reqs = flags;
                me_Length = sz;
            }

            this(void* addr, size_t sz) {
                mea_Addr = addr;
                me_Length = sz;
            }
        }

        ref MemEntry opIndex(size_t index) {
            assert(index < ml_NumEntries);
            auto ptr = cast(MemEntry*)&ml_ME;
            return ptr[index];
        }
    }

    /** AllocEntry -- Alloc memory with MemEntries structure
    *
    *	This function takes a memList structure and allocates enough memory
    *	to hold the required memory as well as a MemEntries structure to keep
    *	track of it.
    *
    *	These MemEntries structures may be linked together in a Process_s
    *	to keep track of the total memory usage of this task. (See
    *	the description of under RemTask() ).
    *
    * Params:
    *	entry = A MemEntries structure filled in with MemEntry structures.
    *
    * Returns:
    *	memList = A different MemEntries filled in with the actual memory
    *	    allocated in the me_Addr field, and their sizes in me_Length.
    *	    If enough memory cannot be obtained, then any memory already
    *	    allocated will be freed, and null is returned.
    *
    * See:
    *	FreeEntry(), CreateMemList(), DeleteMemList()
    */
    MemEntries* allocEntry(MemEntries* entry)
    in (entry, __FUNCTION__ ~ ": Need ptr.")
    in (entry.ml_Node.ln_Type == ListNodeType.LNT_MEMLIST, __FUNCTION__ ~ ": Wrong type.")
    do {
        MemEntries* rc = null;
        logFLine(__FUNCTION__ ~ "( %08x )", entry);

        obtainSemaphore(this.sys_MemHeadersSema, false);
        auto ptr = cast(MemEntries.MemEntry*) entry.ml_ME;
        int i;
        for (i = 0; i < entry.ml_NumEntries; i++) {
            ptr[i].mea_Addr = allocMem(ptr[i].me_Length, ptr[i].mea_Reqs);

            if (ptr[i].mea_Addr == null) {
                for (--i; i >= 0; i--) {
                    freeMem(ptr[i].mea_Addr, ptr[i].me_Length);
                }
                break;
            }
        }
        if (i == entry.ml_NumEntries)
            rc = entry;
        releaseSemaphore(this.sys_MemHeadersSema);

        return rc;
    }

    /** FreeEntry -- Free memory from MemEntries
    *
    *	This function takes a memList structure (as returned by AllocEntry)
    *	and frees all the entries.
    *
    * Params:
    *	entry = pointer to MemEntries structure filled in with MemEntry
    *		   structures
    *
    * See:
    *	AllocEntry(), CreateMemList(), DeleteMemList()
    */
    void freeEntry(MemEntries* entry)
    in (entry, __FUNCTION__ ~ ": Need ptr.")
    in (entry.ml_Node.ln_Type == ListNodeType.LNT_MEMLIST, __FUNCTION__ ~ ": Wrong type.")
    do {
        int i;
        logFLine(__FUNCTION__ ~ "( %08x )", entry);

        obtainSemaphore(this.sys_MemHeadersSema, false);
        auto ptr = cast(MemEntries.MemEntry*) entry.ml_ME;
        for (i = entry.ml_NumEntries - 1; i >= 0; i--) {
            freeMem(ptr[i].mea_Addr, ptr[i].me_Length);
        }
        releaseSemaphore(this.sys_MemHeadersSema);

    }

    /** CalculateMemListSize -- Calculate the required size of a MemEntries
    *
    *	This function calculated the number of bytes required to store a MemEntries
    *   with a given number of Entries.
    *
    * Params:
    *   entries = Numer of required entries. Must be greater or equal 1.
    *
    * Returns:
    *	number of bytes required for a MemEntries, or -1 in case of error !
    *
    * See:
    *	AllocEntry(), FreeEntry(), CreateMemList(), DeleteMemList()
    */
    size_t calculateMemListSize(ulong entries) {
        size_t size = -1;
        if (entries >= 1) {
            size = MemEntries.sizeof + ((entries - 1) * MemEntries.MemEntry.sizeof);
        }
        return size;
    }

    /** CreateMemList -- Create a MemEntries with given number of Entries.
    *
    *	This function allocates a MemEntries structure large enought to hold a given
    *   number of entries. The structure is properly initialized as node type and
    *   NumEntries are set correctly.
    *
    * Params:
    *	entries = number of entries for the MemEntries to allocate.
    *
    * Returns:
    *	Pointer to a MemEntries of requested size or null
    *
    * See:
    *	AllocEntry(), FreeEntry(), DeleteMemList()
    */
    MemEntries* createMemEntries(int entries) {
        MemEntries* ml = null;
        size_t size = calculateMemListSize(entries);
        if (size > 0) {
            ml = cast(MemEntries*) allocMem(size, MemFlags.MEMF_PUBLIC | MemFlags.MEMF_CLEAR);
            if (ml) {
                ml.ml_Node.ln_Type = ListNodeType.LNT_MEMLIST;
                ml.ml_NumEntries = entries;
            }
        }
        return ml;
    }

    /** DeleteMemList -- Free a MemEntries previously allocated with CreateMemList
    *
    *	This function frees a MemEntries structure previously allocated with
    *   CreateMemList(). This functions does no checks, if the memory allocated
    *   with this MemEntries is already freed.
    *
    * Params:
    *	memList = pointer to MemEntries structure to free
    *
    * Notes:
    *	The structure must be allocated with CreateMemList before, or initialized
    *   correctly by hand. Memory allocated with this MemEntries must be already freed
    *   with FreeEntry() before this function is called.
    *
    * See:
    *	AllocEntry(), FreeEntry(), CreateMemList()
    */
    void deleteMemEntries(MemEntries* memList)
    in (memList, __FUNCTION__ ~ ": Need ptr.")
    in (memList.ml_Node.ln_Type == ListNodeType.LNT_MEMLIST, __FUNCTION__ ~ ": Wrong type.")
    in (memList.ml_NumEntries >= 1, __FUNCTION__ ~ ": At least one entry.")
    do {
        size_t freesize = calculateMemListSize(memList.ml_NumEntries);
        if (freesize > 0) {
            freeMem(memList, freesize);
        }
    }

}

@("Memory: Basic Ops")
unittest {
    import std.random : Random, uniform;

    auto rnd = Random(0x4362897);

    DEBUG = false;
    Memory mem = new Memory();

    const size_t testSize = 1024 * 1024;

    __gshared align(1024) ubyte[testSize] memory;
    auto mh = mem.addMemHeader(testSize, MemFlags().MEMF_PUBLIC, short(0), memory.ptr, "PublicMemory");
    assert(mh);

    __gshared align(1024) ubyte[testSize] memory2;
    auto mh2 = mem.addMemHeader(testSize, MemFlags().MEMF_FAST, short(5), memory2.ptr, "FastMemory");
    assert(mh2);

    auto availMem1 = mem.availMem(MemFlags.MEMF_ANY);
    auto largestMem1 = mem.availMem(MemFlags.MEMF_LARGEST);
    auto totalMem1 = mem.availMem(MemFlags.MEMF_TOTAL);

    const size_t miniTestSize = 64;

    assertThrown!AssertError(mem.freeMem(cast(void*) 0x1234, 42));

    auto memAlloc1 = mem.allocMem(miniTestSize, MemFlags.MEMF_PUBLIC);
    assert(memAlloc1);
    memset(memAlloc1, 0, miniTestSize);

    assert(mem.typeOfMem(memAlloc1 + 3) & MemFlags.MEMF_PUBLIC);
    assert(mem.typeOfMem(cast(void*) 0x1234) == MemFlags.MEMF_ANY);

    mem.freeMem(memAlloc1, miniTestSize);
    assert(mem.availMem(MemFlags.MEMF_ANY) == availMem1);

    auto memAlloc2 = mem.allocVec(miniTestSize, MemFlags.MEMF_FAST);
    assert((cast(size_t) memAlloc2 & (2 ^^ 5 - 1)) == 8, "not vectored.");
    memset(memAlloc2, 0, miniTestSize);
    mem.freeVec(memAlloc2);

    auto memAlloc2f = mem.allocVec(miniTestSize, MemFlags.MEMF_PUBLIC);
    assert((cast(size_t) memAlloc2f & (2 ^^ 5 - 1)) == 8, "not vectored.");
    memset(memAlloc2f, 0, miniTestSize);
    mem.freeVec(memAlloc2f);

    auto memAlloc3 = mem.allocAlign(miniTestSize, 7, MemFlags.MEMF_FAST);
    assert((cast(size_t) memAlloc3 & (2 ^^ 7 - 1)) == 0, "not aligned.");
    memset(memAlloc3, 0, miniTestSize);
    mem.freeMem(memAlloc3, miniTestSize);

    auto memAlloc3f = mem.allocAlign(miniTestSize, 7, MemFlags.MEMF_PUBLIC);
    assert((cast(size_t) memAlloc3f & (2 ^^ 7 - 1)) == 0, "not aligned.");
    memset(memAlloc3f, 0, miniTestSize);
    mem.freeMem(memAlloc3f, miniTestSize);

    // FIXME: Weak assumption here... memAlloc3f + 0x1000 <- is this viable?
    auto memAlloc4 = mem.allocAbs(miniTestSize, memAlloc3 + 0x1000, MemFlags());
    assert(memAlloc4);
    memset(memAlloc4, 0, miniTestSize);
    mem.freeMem(memAlloc4, miniTestSize);

    // FIXME: Weak assumption here... memAlloc3f + 0x1000 <- is this viable?
    auto memAlloc4f = mem.allocAbs(miniTestSize, memAlloc3f + 0x1000, MemFlags());
    assert(memAlloc4f);
    memset(memAlloc4f, 0, miniTestSize);
    mem.freeMem(memAlloc4f, miniTestSize);

    auto availMem2 = mem.availMem(MemFlags.MEMF_ANY);
    assert(availMem1 == availMem2);

    auto sysMemHandler = mem.addMemHandler("System Handler", short(0), &mem.systemMemHandler, null);

    string myHandlerData = "Test String";
    auto memHandler = mem.addMemHandler("User Handler", short(0), &myMemHandler, cast(void*) myHandlerData
            .ptr);

    myHandlerReturn = MEM_TRY_AGAIN;
    logFLine("alloc list");
    TinyHead tl = TinyHead();
    tl.initListHead();
    logFLine("Fill 75%%");
    while (mem.availMem(MemFlags()) > mem.availMem(MemFlags.MEMF_TOTAL) / 4) {
        size_t sz = uniform(TinyNode.sizeof, 1024);
        MemFlags mflgs = sz & 1 ? MemFlags.MEMF_REVERSE : MemFlags();
        auto node = cast(TinyNode*) mem.allocVec(sz, mflgs | MemFlags.MEMF_CLEAR);
        if (node) {
            *node = TinyNode();
            node.addNode(tl);
        }
    }
    logFLine("Free 50%%");
    while (auto node = tl.remNodeTail) {
        mem.freeVec(node);
        if (mem.availMem(MemFlags()) > 3 * mem.availMem(MemFlags.MEMF_TOTAL) / 4)
            break;
    }
    logFLine("Fill 100%%");
    while (true) {
        size_t sz = uniform(TinyNode.sizeof, 1024);
        MemFlags mflgs = sz & 1 ? MemFlags.MEMF_REVERSE : MemFlags();
        auto node = cast(TinyNode*) mem.allocVec(sz, mflgs | MemFlags.MEMF_CLEAR);
        if (node) {
            *node = TinyNode();
            node.addNode(tl);
        } else
            break;
    }
    // Memory is full now...
    auto allocFail1 = mem.allocAlign(0x100000, 3, MemFlags());
    assert(allocFail1 == null);

    logFLine("Free all");
    while (auto node = tl.remNodeTail) {
        mem.freeVec(node);
    }

    mem.remMemHandler(memHandler);
    mem.remMemHandler(sysMemHandler);

    // Memory should be empty now....
    auto availMem3 = mem.availMem(MemFlags.MEMF_ANY);
    assert(availMem1 == availMem3);

    mem.remMemHeader(mh);
    logFLine("Done");
}

int myHandlerReturn = MEM_TRY_AGAIN;

STATUS myMemHandler(Memory memory, MemHandler* mmh, MemHandlerData* mhd) {
    logFLine("SysMemHandler called(%s, %x) = MEM_DID_NOTHING");
    auto rc = myHandlerReturn;
    myHandlerReturn = MEM_DID_NOTHING;
    return rc;
}

@("MemEntries: Bulk allocations")
unittest {
    DEBUG = false;
    Memory mem = new Memory();

    const size_t testSize = 1024 * 1024;
    __gshared align(1024) ubyte[testSize] memory;
    auto mh = mem.addMemHeader(testSize, MemFlags().MEMF_PUBLIC, short(0), memory.ptr, "Memory");
    assert(mh);

    auto availMem1 = mem.availMem(MemFlags.MEMF_ANY);

    const size_t miniTestSize = 64;

    auto mementries = mem.createMemEntries(3);
    mementries.opIndex(0) = Memory.MemEntries.MemEntry(MemFlags(), 0x10);
    mementries.opIndex(1) = Memory.MemEntries.MemEntry(MemFlags(), 0x20);
    mementries.opIndex(2) = Memory.MemEntries.MemEntry(MemFlags(), 0x30);

    auto me = mem.allocEntry(mementries);
    if (me)
        mem.freeEntry(me);

    mementries.opIndex(0) = Memory.MemEntries.MemEntry(MemFlags(), 0x10);
    mementries.opIndex(1) = Memory.MemEntries.MemEntry(MemFlags(), 0x20);
    mementries.opIndex(2) = Memory.MemEntries.MemEntry(MemFlags(), 0x3000000); // <- to big!
    me = mem.allocEntry(mementries);
    assert(me == null); // Must be null.

    mementries.opIndex(2) = Memory.MemEntries.MemEntry(cast(void*) 123, 0x3000000);

    mem.deleteMemEntries(mementries);

    auto availMem3 = mem.availMem(MemFlags.MEMF_ANY);
    assert(availMem1 == availMem3);

    mem.remMemHeader(mh);
    logFLine("Done");
}
