/** Implementation of the Amiga linked lists in D
**
** Authors: Carsten Schlote
** Copyright: Carsten Schlote, 2024
** License: GPL-3.0-only
*/
module va_toolbox.linked_list;

import core.exception;
import std.exception;
import std.conv;

/*****************************************************************************
** NOTE:
** We use and propose short prefixes for structure elements. This allows
** simple specific search, or later replacement. You should use this for your
** code too.
*/

/** A D implementation of a double-linked list
 *
 * This is a minimalistic approach. No extra features. Just the the list.
 * It can be embedded into any struct/class declaration.
 *
 * The list uses a head and tail node. User nodes are placed between these
 * two nodes. The empty list consists of just these two nodes.
 */

struct LinkedList(alias EHT, alias ENT) {

    /** The List Node.
    *
    * This structure is the usually first element of a structure, but could
    * be located everywhere in the structure. It can be used
    */
    struct LinkedListNode {
        LinkedListNode* ln_Succ; /// Pointer to next ListNode (Successor)
        LinkedListNode* ln_Pred; /// Pointer to previous ListNode (Predecessor)

        mixin ENT; /// Embedded payload data

        /// The tail node has no successor and is part of ListHead
        bool isNodeTail() => (this.ln_Succ == null) ? true : false;

        /// The head node has no predecessor and is part of ListHead
        bool isNodeHead() => (this.ln_Pred == null) ? true : false;

        /// Is a node a real node, neithe rhead nor tail
        bool isNodeReal() => !(isNodeTail() || isNodeHead());

        /// Is a not unlinked?
        bool isNodeUnlinked() => this.ln_Succ == null && this.ln_Pred == null;

        /// Some aliasing, use this with isTailNode
        LinkedListNode* getNextNode()
        in (!isNodeTail, "Iterate to next on tail node?")
        do {
            return this.ln_Succ;
        }

        /// Some aliasing, use this with isHeadNode
        LinkedListNode* getPrevNode()
        in (!isNodeHead, "Iterate to previous on head node?")
        do {
            return this.ln_Pred;
        }

        /** linkNode -- link a node into a list
         *
         * Params:
         *   prevNode = ptr to previous node (or head node)
         *   nextNode = ptr to next node (or tail node)
         *
         * Note: No checks at all!
         */
        package void linkNode(scope LinkedListNode* prevNode, scope LinkedListNode* nextNode) {
            // Update our own links to next and previous node
            this.ln_Succ = nextNode;
            this.ln_Pred = prevNode;

            // Then overwrite the links from previous and next node to our node
            prevNode.ln_Succ = &this;
            nextNode.ln_Pred = &this;
        }

        /** addNode -- insert a node into a list
        *
        * Insert a node into a doubly linked list AFTER a given node
        * position.  Insertion at the head of a list is possible by passing a
        * zero value for node, though the addNodeHead function is slightly
        * faster for that special case. Passing the tailNode of the list adds
        * the node to the end of the list. Again addNodeTail() might be faster.
        *
        *   this - the node to insert AFTER...
        *
        * Params:
        *   list = a pointer to the target list header
        *   prevNode = the node after which to insert, or null to add to list head
        *
        * Returns:
        *   Your list is larger by one node.
        *
        * Example:
        *   ListHead myList;
        *
        *   ListNode* myNode, listNode;
        *   	...
        *   myNode.addNodeHead( myList, listNode );
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling thread must be the owner of the involved list.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        */
        void addNode(scope ref LinkedListHead list, scope LinkedListNode* prevNode = null)
        in (isNodeUnlinked, __PRETTY_FUNCTION__ ~ ": Node already added?")
        do {
            if (!prevNode)
                prevNode = list.getHeadNode;

            if (prevNode.isNodeTail)
                prevNode = prevNode.getPrevNode; // Move listNode one node back to head or real node.

            auto next = prevNode.getNextNode;

            linkNode(prevNode, next);
        }

        /** unlinkNode -- unlink a linked node from list
         *
         * Note: No checks at all!
         */
        package void unlinkNode() {
            auto nextnode = this.ln_Succ; // get prev and next nodes
            auto prevnode = this.ln_Pred;
            prevnode.ln_Succ = nextnode; // merge these nodes
            nextnode.ln_Pred = prevnode;
            this.ln_Succ = null; // Clear invalid pointers
            this.ln_Pred = null;
        }

        /** remNode -- remove a node from a list
        *
        * Unlink a node from whatever list it is in.  Nodes that are not part
        * of a list must not be passed to this function!
        *
        * Params:
        *   this - the node to remove
        *
        * Returns:
        *   Your list is smaller by one node or empty. The returned value is your
        *   removed node.
        *
        * Example:
        *   ListNode* myNode,myRemNode;
        *       ...
        *   	myRemNode = remNode( myNode );		// myRemNode == myNode
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling task must be the owner of the involved list.
        *   _Important note_:
        *      The ln_Pred and ln_Succ pointers of the removed node are no
        *      longer valid after removal from list. Do not use them after
        *      removal.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        */
        LinkedListNode* remNode()
        in (isNodeReal, __PRETTY_FUNCTION__ ~ ": Can only remove linked nodes.")
        do {
            unlinkNode();
            return &this;
        }
    }

    /** The List Header - simply two merged list nodes.
    **
    ** The ListHead is the Head and Tail node in a single structure.
    **
    **   /->Next                                  # lh_Head :    HEAD
    **   |  Prev  Next (=PrevNext)= null          # lh_Tail :    HEAD  TAIL
    **   \------->Prev                            # lh_TailPred:       TAIL
    **
    ** Note:
    ** - head and tail pointing to each other, but the head has no predessor
    **   and the tail node has no successor.
    ** - The lh_Tail is always 'null'. It aliases the ln_Pred of head and the
    **   ln_Succ of the tail node.
    */
    struct LinkedListHead {
        /* The following aliases the links of the head and tail nodes */
    private:
        LinkedListNode* lh_Head;
        LinkedListNode* lh_Tail;
        LinkedListNode* lh_TailPred;
    public:
        mixin EHT;

        /** Get the 'head node'
        *
        * Note: The cast operation is hidden inside this function.
        * Returns: Ptr to the 'head node'
        */
        auto getHeadNode() => cast(LinkedListNode*)(&(this.lh_Head));

        /** Get the 'tail node'
        *
        * Note: The cast operation is hidden inside this function.
        * Returns: Ptr to the 'tail node'
        */
        auto getTailNode() => cast(LinkedListNode*)(&(this.lh_Tail));

        /** Is this list empty?
        *
        * Returns:
        *   true if empty, false otherwise
        */
        bool isListEmpty() {
            return getHeadNode.getNextNode.isNodeTail();
        }

        /** initListHead -- Inititalize a ListHead
        *
        * Before you can use list functions on a ListHead you must
        * initialize the structure.
        *
        * Params:
        *   list -- ptr to a uninitialized ListHead structure
        *
        * Returns:
        *   An initialized ListHead.
        *
        * Example:
        *   ListHead myList;
        *   myList.initListHead();
        *
        * Notes:
        *   Any information in the ListHead will be destroyed. Do not use it on
        *   already initialized ListHeads, or you may lose the actual linked list.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        */
        void initListHead() {
            this.lh_Head = this.getTailNode;
            this.lh_Tail = null;
            this.lh_TailPred = this.getHeadNode;
        }

        /** addNodeHead -- insert node at the head of a list
        *
        * Add a node to the head of a doubly linked list. The code links
        * the node after the HEAD node and in front of the existing nodes.
        * There is always a TAIL node at least.
        *
        *   this - a pointer to the target list header
        * Params:
        *   node = the node to insert
        *
        * Returns:
        *   Your list is larger by one node.
        *
        * Example:
        *   ListHead myList;
        *   ListNode* myNode;
        *   ...
        * 	myList.addNodeHead( myNode );
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling task must be the owner of the involved list.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        */
        void addNodeHead(ref LinkedListNode node)
        in (node.isNodeUnlinked, __PRETTY_FUNCTION__ ~ ": Trying to add already linked node.")
        do {
            // Link between head node and current 'first' node (or tai)
            node.linkNode(this.getHeadNode, this.getHeadNode.getNextNode);
        }

        /** remNodeHead -- remove node at the head of a list
        *
        * Remove a node to the head of a doubly linked list.
        *
        * Params:
        *   this - the list to remove a head node from
        *
        * Returns:
        *   Your list is smaller by one node or empty. The returned value is your
        *   removed node or null if List was empty
        *
        * Example:
        *   ListHead* myList;
        *       ...
        *   	while ( myList.remNodeHead() )
        *       {
        *   		// process removed node....
        *   	}
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling task must be the owner of the involved list.
        *   _Important note_:
        *      The ln_Pred and ln_Succ pointers of the removed node are no
        *      longer valid after removal from list. Do not use them after
        *      removal.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        */
        LinkedListNode* remNodeHead()
        in (this.isListEmpty || this.getHeadNode.getNextNode.isNodeReal, __PRETTY_FUNCTION__ ~ ": Trying to remove unlinked node.")
        do {
            // Get the first node or tail node
            auto node = this.getHeadNode.getNextNode();
            if (node.isNodeTail())
                return null;

            node.unlinkNode();
            return node;
        }

        /** addNodeTail -- insert node at the head of a list
        *
        * Add a node to the tail of a doubly linked list. So our node is linked
        * after the last existing node or the HEAD node, and in front of the TAIL node.
        * There is always a HEAD node.
        *
        *   this - a pointer to the target list header
        * Params:
        *   node = the node to insert
        *
        * Returns:
        *   Your list is larger by one node and your node is added at tail of list.
        *
        * Example:
        *   ListHead myList;
        *   ListNode* myNode;
        *   	...
        *   	myList.addNodeTail(myNode );
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling task must be the owner of the involved list.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        *
        */
        void addNodeTail(ref LinkedListNode node)
        in (node.isNodeUnlinked, __PRETTY_FUNCTION__ ~ ": Trying to add already linked node.")
        do {
            // Link between last and tail node
            node.linkNode(this.getTailNode.getPrevNode, this.getTailNode);
        }

        /** remNodeTail -- remove node at the tail of a list
        *
        * Remove a node from the tail of a doubly linked list.
        *
        * Params:
        *   this - the list to remove a tail node from
        *
        * Returns:
        *   Your list is smaller by one node or empty. The returned value is your
        *   removed node or null if List was empty
        *
        * Example:
        *   ListHead* myList;
        *       ...
        *   	while ( myList.remNodeTail() )
        *       {
        *   		// process removed node....
        *   	}
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling task must be the owner of the involved list.
        *   _Important note_:
        *      The ln_Pred and ln_Succ pointers of the removed node are no
        *      longer valid after removal from list. Do not use them after
        *      removal.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        */
        LinkedListNode* remNodeTail()
        in (this.isListEmpty || this.getTailNode.getPrevNode.isNodeReal, __PRETTY_FUNCTION__ ~ ": Trying to remove unlinked node.")
        do {
            // Get the last node or head node
            auto node = this.getTailNode.getPrevNode();
            if (node.isNodeHead())
                return null;

            node.unlinkNode();
            return node;
        }

        /** addNode -- insert a node into a list
        *
        * Insert a node into a doubly linked list AFTER a given node
        * position.  Insertion at the head of a list is possible by passing a
        * zero value for node, though the addNodeHead function is slightly
        * faster for that special case.
        *
        *   this - a pointer to the target list header
        * Params:
        *   node = the node to insert
        *   listNode = the node after which to insert
        *
        * Returns:
        *   Your list is larger by one node.
        *
        * Example:
        *   ListHead myList;
        *   ListNode* myNode,listNode;
        *   	...
        *   	myList.addNodeHead( myNode, listNode );
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling task must be the owner of the involved list.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        *
        */
        void addNode(scope ref LinkedListNode node, scope LinkedListNode* listNode = null) {
            node.addNode(this, listNode);
        }

        /** remNode -- remove a node from a list
        *
        * Unlink a node from whatever list it is in.  Nodes that are not part
        * of a list must not be passed to this function!
        *
        * Params:
        *   node = the node to remove
        *
        * Returns:
        *   Your list is smaller by one node or empty. The returned value is your
        *   removed node.
        *
        * Example:
        *   ListNode* myList, myRemNode;
        *   ...
        *   myRemNode = list.remNode( myNode );		// myRemNode == myNode
        *
        * Notes:
        *   This function does not arbitrate for access to the list.  The
        *   calling task must be the owner of the involved list.
        *   _Important note_:
        *      The ln_Pred and ln_Succ pointers of the removed node are no
        *      longer valid after removal from list. Do not use them after
        *      removal.
        *
        * Bugs:
        *   none
        *
        * See:
        *   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
        *   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
        *
        */
        LinkedListNode* remNode(ref LinkedListNode node) {
            return node.remNode;
        }

        /// opApply for foreach
        int opApply(scope int delegate(ref LinkedListNode) dg) {
            for (LinkedListNode* node = this.getHeadNode.getNextNode(); !node.isNodeTail();
                node = node.getNextNode()) {

                int result = dg(*node);
                if (result)
                    return result;
            }
            return 0;
        }

        /// opApply for foreach
        int opApply(scope int delegate(int idx, ref LinkedListNode) dg) {
            int idx = 0;
            for (LinkedListNode* node = this.getHeadNode.getNextNode(); !node.isNodeTail();
                node = node.getNextNode()) {

                int result = dg(idx++, *node);
                if (result)
                    return result;
            }
            return 0;
        }
    }
}

mixin template LinkedListEmptyMixin() {
}
alias TinyList = LinkedList!(LinkedListEmptyMixin, LinkedListEmptyMixin);
alias TinyNode = TinyList.LinkedListNode;
alias TinyHead = TinyList.LinkedListHead;

/** Generator to create a ListHead on heap */
T.LinkedListHead* makeHead(T)() {
    auto listHead = new T.LinkedListHead();
    listHead.initListHead;
    return listHead;
}

/** Generator to create a ListNode on heap, optionally setting other fields */
T.LinkedListNode* makeNode(T)() {
    auto listNode = new T.LinkedListNode();
    return listNode;
}

/* -------- Example of extended LinkedList data -------------------- */

/** Type definitions for 'extended' LinkedListNodes
 *
 * Examples for a set of node type as it was used in ancient OSes.
 */
enum ListNodeType : ushort {
    LNT_UNKNOWN = 0x0000, // For anything not found below

    //-- Nodes for system.library services ---
    LNT_RESOURCE = 0x0001, // A Hardware description node
    LNT_MEMORY = 0x0100, // For physical Memory management
    LNT_VIRTMEM = 0x0101, // For virtual Memory management
    LNT_PAGEMEM = 0x0102, // For paged memory management
    LNT_MEMLIST = 0x0103, // For MemList Structures
    LNT_MEMPOOL = 0x0104, // For MemPools
    LNT_MEMHANDLER = 0x0105, // For MemHandler

    LNT_MSGQUEUE = 0x0200, // For the MsgPort list
    LNT_MSGIDLE = 0x0201, // Message currently not in use
    LNT_MSGSENT = 0x0202, // Message has been send
    LNT_MSGRECEIVED = 0x0203, // Message has been received
    LNT_MSGREPLIED = 0x0204, // Message has been replied
    LNT_MSGDEATH = 0x0205, // Message died beca= use of, failure

    LNT_SEMAPHORE = 0x0300, // Element of Semaphore list

    LNT_MODULE = 0x0400, // Element of Module list
    LNT_DRIVER = 0x0401, // Element of Driver list
    LNT_SHARED = 0x0402, // Element of Shared list
    LNT_SUBCODE = 0x0404, // Just a job in modInit()

    LNT_LOWIRQ = 0x0500, // For IRQ management lists.
    LNT_IRQSERVER = 0x0501, // Highlevel IRQ server handler node

    LNT_PROCESS = 0x0600, // A system process
    LNT_THREAD = 0x0601, // A process thread

    LNT_NAMEDNODE = 0x0e00, // A named node
    LNT_NAMEDNODEP = 0x0e01, // A named node in a MemPool

    //**-- Defined CaOS subsystems Nodes. Details on subsystem LNT_???
    //**-- you may find in the subsystem headerfile.

    LNT_GRAPHICS = 0x1000, // reserved for subsystem (0x1000-0x1fff)
    LNT_AUDIO = 0x2000, // reserved for subsystem (0x2000-0x2fff)
    LNT_INPUT = 0x3000, // reserved for subsystem (0x3000-0x3fff)
    LNT_GUIMGR = 0x4000, // reserved for subsystem (0x4000-0x4fff)
    LNT_NETWORK = 0x5000, // reserved for subsystem (0x5000-0x5fff)
    LNT_DOS = 0x6000, // reserved for subsystem (0x6000-0x6fff)
    LNT_SETTINGS = 0x7000, // reserved for subsystem (0x7000-0x70ff)

    //**-- User Programs may use any number higher ,,,

    LNT_USERTYPE = 0x8000 // User node types starts here
}

/** The type and the human readable name of the list head.
 *
 * Can be used to enforce node types matching the list type.
 */
mixin template LinkListHeadExtras() {

    ListNodeType lh_Type; /// A type number
    string lh_Name; /// Pointer to a C String
}

/** The type and the human readable name of the list node.
 *
 * Can be used to enforce node types matching the list type,
 * name nodes or sort them by priority.
 */
mixin template LinkListNodeExtras() {
    ListNodeType ln_Type; /// A type number
    short ln_Priority; /// Signed priority, for sorting
    string ln_Name; /// Pointer to a C String
}

alias List = LinkedList!(LinkListHeadExtras, LinkListNodeExtras);
alias ListNode = List.LinkedListNode;
alias ListHead = List.LinkedListHead;

/** Generator to create a ListHead on heap */
ListHead* makeHead(ListNodeType type = ListNodeType.LNT_UNKNOWN, string name = null) {
    auto listHead = new ListHead();
    listHead.initListHead;
    listHead.lh_Type = type;
    listHead.lh_Name = name;
    return listHead;
}

/** Generator to create a ListNode on heap, optionally setting other fields */
ListNode* makeNode(ListNodeType type = ListNodeType.LNT_UNKNOWN, short pri = 0, string name = null) {
    auto listNode = new ListNode();
    // listNode.data = LinkListNodeExtras(type, pri, name);
    listNode.ln_Type = type;
    listNode.ln_Priority = pri;
    listNode.ln_Name = name;
    return listNode;
}

/** addNodeSorted -- insert a node into a list by ln_Priority field
*
* Insert or append a node to a system queue.  The insert is
* performed based on the node priority -- it will keep the list
* properly sorted.  New nodes will be inserted in front of the first
* node with a lower priority.   Hence a FIFO queue for nodes of equal
* priority results
*
* Params:
*   listHead = a pointer to the target list header
*   node = the node to insert
*
* Returns:
*   Your list is larger by one node.
*
* Example:
*   ListHead myList;
*   ListNode* myNode;
*  	...
*  	myList.addNodeSorted( , myNode );
*
* Notes:
*   This function does not arbitrate for access to the list.  The
*   calling task must be the owner of the involved list.
*
* Bugs:
*   none
*
* See:
*   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
*   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
*/
void addNodeSorted(ListHead* listHead, ref ListNode node) {

    ListNode* insertNode;
    for (
        insertNode = listHead.getHeadNode.getNextNode; !insertNode.isNodeTail; insertNode = insertNode.getNextNode()) {
        if (node.ln_Priority >= insertNode.ln_Priority)
            break;
    }
    node.addNode(*listHead, insertNode);
}

/** findNode -- find a node by name
*
* Traverse a system list until a node with the given name is found.
* To find multiple occurrences of a string, this function may be
* called with a node starting point.
*
* No arbitration is done for access to the list! If multiple tasks
* access the same list, an arbitration mechanism such as
* Semaphores must be used.
*
* Params:
*   list = a pointer to the target list header
*   name = a pointer to a name string terminated with null
*
* Returns:
*   A pointer to the node with the same name, else
*   null to indicate that the string was not found.
*
* Example:
*   ListNode* myNode;
*   	...
*   	if ( myNode = myList.findNode("FooBar" ))
*   	{
*   		...
*   	}
*
* Notes:
*   This function does not arbitrate for access to the list.  The
*   calling task must be the owner of the involved list.
*
* Bugs:
*   none
*
* See:
*   initListHead(), addNode(), remNode(), addNodeHead(), remNodeHead(),
*   addNodeTail(), remNodeTail(), addNodeSorted(), findNode()
*
*/
ListNode* findNode(ListHead* list, string name) {
    for (ListNode* node = list.getHeadNode.getNextNode(); !node.isNodeTail();
        node = node.getNextNode()) {
        if (node.ln_Name.length && node.ln_Name == name)
            return node;
    }
    return null;
}

/* ---------------------------------------------------------------------*/

mixin template LinkedListExtraTest()
{
    ubyte[4096] block;
}
alias BlockList = LinkedList!(LinkListNodeExtras, LinkedListExtraTest);
alias BlockListNode = BlockList.LinkedListNode;
alias BlockListHead = BlockList.LinkedListHead;

/** Generator to create a ListHead on heap */
// BlockListHead* makeHead() {
//     auto listHead = new BlockListHead();
//     listHead.initListHead;
//     return listHead;
// }

/** Generator to create a ListNode on heap, optionally setting other fields */
BlockListNode* makeNode(ubyte[] block) {
    auto listNode = new BlockListNode();
    listNode.block = block;
    return listNode;
}

/* ---------------------------------------------------------------------*/

version (unittest) {

    void testLinkedListNode(T)() {
        static if (is(T == List))
            T.LinkedListHead* lh = makeHead(ListNodeType.LNT_AUDIO, "test list");
        else
            T.LinkedListHead* lh = makeHead!T();

        assertThrown!AssertError(lh.getHeadNode.getPrevNode());
        assertThrown!AssertError(lh.getTailNode.getNextNode());

        static if (is(T == List)) {
            auto node1 = makeNode(ListNodeType.LNT_UNKNOWN, 1, "A");
            auto node2 = makeNode(ListNodeType.LNT_UNKNOWN, 2, "B");
            auto node3 = makeNode(ListNodeType.LNT_UNKNOWN, 3, "C");
        } else {
            auto node1 = makeNode!T();
            auto node2 = makeNode!T();
            auto node3 = makeNode!T();
        }
        auto nodes = [node1, node2, node3];
        foreach (node; nodes)
            assertThrown!AssertError(node.remNode());

        node1.addNode(*lh, lh.getTailNode); // Test special case...
        node2.addNode(*lh);
        node3.addNode(*lh);

        int idx = 3;
        for (auto nd = lh.getHeadNode.getNextNode; !nd.isNodeTail; nd = nd.getNextNode) {
            static if (is(T == List)) {
                assert(nd.ln_Priority == idx);
            }
            idx--;
        }
        assert(idx == 0);
        node1.remNode();
        node3.remNode();
        node2.remNode();
        assert(lh.isListEmpty);

        idx = 1;
        node1.addNode(*lh);
        node2.addNode(*lh, node1);
        node3.addNode(*lh, lh.getTailNode); // Test special case...
        for (auto nd = lh.getHeadNode.getNextNode; !nd.isNodeTail; nd = nd.getNextNode) {
            import std.stdio : writeln;

            // writeln(*nd);
            static if (is(T == List)) {
                assert(nd.ln_Priority == idx);
            }
            idx++;
        }
        node1.remNode();
        node3.remNode();
        node2.remNode();
        assert(idx == (3 + 1));

        node1 = node2 = node3 = null;
    }
}
@("LinkedList: TinyList node methods tests")
unittest {
    testLinkedListNode!TinyList();
}

@("LinkedList: List node methods tests")
unittest {
    testLinkedListNode!List();
}

@("LinkedList: BlockList node methods tests")
unittest {
    testLinkedListNode!BlockList();
}

version (unittest) {
    void testLinkedListHead(T)() {
        import std.stdio : writeln, writefln;
        import std.format : format;

        static if (is(T == List))
            T.LinkedListHead* lh = makeHead(ListNodeType.LNT_DOS, "test list");
        else
            T.LinkedListHead* lh = makeHead!T();
        assert(lh.isListEmpty == true);
        assert(lh.getHeadNode.isNodeHead);
        assert(lh.getTailNode.isNodeTail);

        static if (is(T == List)) {
            auto node1 = T.LinkedListNode();
            node1.ln_Type = ListNodeType.LNT_MEMHANDLER;
            node1.ln_Priority = 42;
            node1.ln_Name = "Test 1";
        } else {
            auto node1 = T.LinkedListNode();
        }

        lh.addNodeHead(node1);
        assert(lh.isListEmpty == false);

        assert(node1.isNodeReal);
        assert(node1.getPrevNode.isNodeHead);
        assert(node1.getNextNode.isNodeTail);

        static if (is(T == List)) {
            auto node2 = T.LinkedListNode();
            node2.ln_Type = ListNodeType.LNT_AUDIO;
            node2.ln_Priority = 43;
            node2.ln_Name = "Test 2";
        } else {
            auto node2 = T.LinkedListNode();
        }

        lh.addNodeTail(node2);
        assert(node2.isNodeReal);
        assert(!node2.getPrevNode.isNodeHead);
        assert(node2.getNextNode.isNodeTail);

        int cnt = 0;
        for (T.LinkedListNode* nd = lh.getHeadNode.getNextNode; !nd.isNodeTail; nd = nd.getNextNode) {
            cnt++;
        }
        assert(cnt == 2);

        static if (is(T == List)) {
            auto node3 = T.LinkedListNode();
            node3.ln_Type = ListNodeType.LNT_AUDIO;
            node3.ln_Priority = 54;
            node3.ln_Name = "Test 3";
        } else {
            auto node3 = T.LinkedListNode();
        }

        lh.addNode(node3, &node1);
        assert(node3.isNodeReal);
        assert(!node3.getPrevNode.isNodeHead);
        assert(!node3.getNextNode.isNodeTail);

        cnt = 0;
        for (T.LinkedListNode* nd = lh.getHeadNode.getNextNode; !nd.isNodeTail; nd = nd.getNextNode) {
            cnt++;
        }
        assert(cnt == 3);

        static if (is(T == List)) {
            auto n1 = lh.findNode("Test 1");
            assert(n1 == &node1);
            auto n2 = lh.findNode("Test 2");
            assert(n2 == &node2);
            auto n3 = lh.findNode("Test 3");
            assert(n3 == &node3);
            auto nX = lh.findNode("Test X");
            assert(nX == null);
        }

        static if (is(T == List)) {
            ListNode node4 = T.LinkedListNode();
            node4.ln_Type = ListNodeType.LNT_AUDIO;
            node4.ln_Priority = 50;
            node4.ln_Name = "Test 4";

            lh.addNodeSorted(node4);
            assert(node4.getPrevNode == &node1);
            assert(node4.getNextNode == &node3);
        } else {
            auto node4 = T.LinkedListNode();

            lh.addNode(node4, &node1);
        }

        lh.remNodeHead();
        lh.remNodeTail();
        lh.remNode(node4);
        lh.remNode(node3);
        assert(lh.isListEmpty);

        foreach (short idx; 0 .. 10) {
            static if (is(T == List)) {
                auto node = makeNode(ListNodeType.LNT_UNKNOWN, idx, format("Node%02d", idx));
            } else {
                T.LinkedListNode* node = makeNode!T();
            }
            lh.addNodeTail(*node);
        }
        alias DG = int delegate(ref ListNode);
        foreach (ref key; *lh) {
            // writefln("%s", key);
        }
        foreach (idx, ref key; *lh) {
            // writefln("%02d : %s", idx, key);
        }
        int i = 0;
        foreach (ref key; *lh) {
            // writefln("%s", key);
            static if (is(T == List)) {
                if (key.ln_Priority >= 2)
                    break;
            } else {
                if (i++ > 2)
                    break;
            }
        }
        foreach (idx, ref key; *lh) {
            // writefln("%02d : %s", idx, key);
            if (idx >= 2)
                break;
        }
        while (lh.remNodeHead) {
        }
        while (lh.remNodeTail) {
        }
        assert(lh.isListEmpty);
    }
}
@("LinkedList: TinyList methods tests")
unittest {
    testLinkedListHead!TinyList();
}

@("LinkedList: List methods tests")
unittest {
    testLinkedListHead!List();
}

@("LinkedList: BlockList methods tests")
unittest {
    testLinkedListHead!BlockList();
}

/* ---------------------------------------------------------------------*/

version (unittest) import std.stdio;

class LinkedListRange(T) {

private:
    T.LinkedListHead listHead;
    T.LinkedListNode* frontSlot;
    size_t listLength;
    const bool V = false;

public:
    this() {
        this.listHead = T.LinkedListHead();
        this.listHead.initListHead;
    }

    //------------------------------------------------------------

    @property bool empty() {
        auto rc = listHead.isListEmpty && frontSlot == null;

        if (V)
            writeln(__FUNCTION__, " ", rc, " ", listLength);
        assert(rc == (listLength == 0), "Inconsistency?");
        return listLength == 0;
    }

    @property size_t length() {
        if (frontSlot) {
            listHead.addNodeHead(*frontSlot);
            frontSlot = null;
        }
        return listLength;
    }

    void put(T.LinkedListNode* node) {
        listHead.addNodeTail(*node);
        listLength++;
        assert(listLength > 0);
        if (V)
            writeln(__FUNCTION__, " ", *node, " ", listLength);
    }

    @property T.LinkedListNode* front()
    in (listLength > 0, "Calling front() on empty range.")
    do {
        if (frontSlot is null)
            frontSlot = listHead.remNodeHead;

        if (V)
            writeln(__FUNCTION__, " ", *frontSlot, " ", listLength);
        return frontSlot;
    }

    /// Range popFront() IF - see D manual for details!
    void popFront()
    in (listLength > 0, "Calling popFront() on empty range.")
    do {
        if (frontSlot) {
            frontSlot = null;
        } else {
            listHead.remNodeHead;
        }
        listLength--;
        if (V)
            writeln(__FUNCTION__, " ", listLength);
    }
}

version (unittest) {
    private void testRanges(U)() {
        import std.conv : to;
        import std.algorithm;
        import std.range;
        import std.stdio : writefln, writeln;
        import std.format : format;

        alias T = LinkedListRange!U;
        const bool v = false;

        static assert(hasLength!T);
        static assert(isInputRange!T);
        static assert(isOutputRange!(T, ElementType!T));
        static assert(!isForwardRange!T);
        static assert(!isBidirectionalRange!T);
        static assert(!isRandomAccessRange!T);

        T mockList(char fill, short start, short cnt) {
            T rng = new T();
            foreach (short idx; 0 .. cnt) {
                static if (is(U == List)) {
                    auto str = format("Node%02d", start + idx);
                    U.LinkedListNode* node = makeNode(ListNodeType.LNT_UNKNOWN, (start + idx).to!short, str);
                } else {
                    U.LinkedListNode* node = makeNode!U();
                }
                if (v)
                    writefln("%c%02d: %s", fill, idx, *node);
                rng.put(node);
            }
            return rng;
        }

        auto rng1 = mockList('A', 0, 10);
        assert(rng1.length == 10);
        auto rng2 = mockList('B', 20, 10);
        assert(rng2.length == 10);

        auto chained = chain(rng1, rng2);
        if (v)
            writefln("Chain Length = %d", chained.length);
        assert(chained.length == 20);

        auto data = chained.array;
        if (v)
            writefln("Chain Length = %d", chained.length);
        if (v)
            writefln("Data Length = %d", data.length);
        assert(chained.length == 0);
        assert(data.length == 20);

        auto rng3 = new T();
        copy(data, rng3);
        if (v)
            writefln("Data Length = %d", data.length);
        if (v)
            writefln("RNG3 Length = %d", rng3.length);
        assert(data.length == 20);
        assert(rng3.length == 20);

        auto rng4 = new T();
        assertNotThrown!AssertError(copy(rng3, rng4));
        /* Note: Copying needs special handling here. See class for details! */
        if (v)
            writefln("RNG3 Length = %d", rng3.length);
        if (v)
            writefln("RNG4 Length = %d", rng4.length);
        assert(rng3.length == 0);
        assert(rng4.length == 20);

        foreach (idx, ref node; rng4.listHead) {
            if (v)
                writefln("C%02d: %s", idx, node);
        }
    }
}

@("LinkedList: Test ranges interface for TinyList")
unittest {
    testRanges!(TinyList)();
}

@("LinkedList: Test ranges interface for List")
unittest {
    testRanges!(List)();
}

@("LinkedList: Test ranges interface for BlockList")
unittest {
    testRanges!(BlockList)();
}

/*******************************************************************************
*******************************************************************************
**
**  October 2024 csc
**
**  Once upon time there was a software project. For this software project
**  we recreated some of the linked list stuff we know from Amiga.
**  I wondered, if the the code could be ported to D. Of course, it can.
**
**  The RCS/CVS log fragment below is some kind of time capsule. It reminds me
**  that with the right people you can recreate an OS capable to run Amiga
**  software (source level compatibility, not binary) within a single year.
**
**  With the 'Wrong' people you can throw lots of money and time on it - without
**  any fast progress, low code quality, you name it.
**
**  $Log: lists.c,v $
**
**  Revision 1.13  2001/07/03 15:35:47  csc
**  Cleanups, Debug and AssertCode added.
**
**  Revision 1.12  2001/06/27 13:02:03  csc
**  Added debug hacks to remNode#?() functions. The ln_Succ and ln_Pred ptrs
**  are now trashed to allow dectection of broken list handling.
**
**  Revision 1.11  2001/03/01 12:07:26  csc
**  Corrected the string compare code of findNode(). It caused some sideeffects
**  with codeoptimizer.
**
**  Revision 1.10  2001/02/01 02:36:59  csc
**  Updated autodocs.
**
**  Revision 1.9  2000/07/20 23:58:19  csc
**  Fixed stupid circluar link bug in addNodeHead(). addNodeTail() was correct.
**  I wonder, why this did not appeared as a problem before, as addNodeHead()
**  was already in use by OS. Nevertheless the code is cleaned up now, and
**  works now. (singlestepped !)
**
**  Revision 1.8  2000/07/20 15:23:01  akl
**  applied quick fix to addNodeHead() and addNodeTail() for the special case
**  that the list is empty. Doesn't make anything worse, at least.
**
**  Revision 1.7  2000/06/02 03:48:52  csc
**  Removed most of the GCC warnings.
**
**  Revision 1.6  2000/05/01 23:09:31  csc
**  Implemented new module call macros. Next step must be, to implement compiler
**  depended (DIAB and gcc) __inline__ code instead of macros to eleminate inferences
**  between the MACRO and other elements of the same name.
**
**  Revision 1.5  2000/04/17 12:02:19  csc
**  Revision 1.4  2000/04/17 11:02:32  csc
**  Cleaned up autodocs.
**
**  Revision 1.3  2000/04/11 07:21:05  csc
**  Stripped unneeded TinyList structure.
**
**  Revision 1.2  2000/04/10 13:50:50  csc
**  Changed structure element names for ListHeads and ListNode to their classical
**  form.
**
**  Revision 1.1.1.1  2000/03/18 23:19:48  csc
**  Cleanup of Sources.
**  Release 0.8
**
**  Revision 1.29  2000/02/09 08:32:38  csc
**  It's caOS now... :-)
**
**  Revision 1.28  2000/01/29 13:38:58  schlote
**  CaOS Release 0.7
**
**  Revision 1.27  2000/01/25 14:44:38  csc
**  Revision 1.26  2000/01/25 15:12:42  csc
**  CaOS Release 0.6
**
**  Revision 1.25  2000/01/14 01:40:05  schlote
**  ModulOS Release 0.5
**
**  Revision 1.24  2000/01/06 00:37:22  schlote
**  Changed Calling macros.
**
**  Revision 1.23  2000/01/05 20:18:24  schlote
**  CaOS Release 0.4
**
**  Revision 1.21  2000/01/02 22:39:31  schlote
**  CaOS Release 0.3 : More modules added.
**
**  Revision 1.20  1999/12/30 15:27:55  schlote
**  ModulOS Release 0.2
**
**  Revision 1.12  1999/09/30 20:27:34  schlote
**  Stable release
**
**  Revision 1.11  1999/09/18 21:07:05  schlote
**  Added stubs for any missing function. Now fill in the remaining code.
**
**  Revision 1.10  1999/08/28 21:54:23  schlote
**  Bugfixes, esp. lists and memory.
**
**  Revision 1.9  1999/08/28 18:08:45  schlote
**  This is a first version with workin allocator.
**
**  Revision 1.8  1999/08/24 19:34:55  schlote
**  First rlease with working memory allocation. Will work and exit.
**
**  Revision 1.7  1999/08/23 20:50:53  schlote
**  Added AddMemHeader
**
**  Revision 1.6  1999/08/21 22:13:59  schlote
**  First step is done.
**
**  Revision 1.5  1999/08/21 17:06:33  schlote
**  First piece of code
**
****************************************************************************
*/
