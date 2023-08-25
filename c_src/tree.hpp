#ifndef __TREE_HPP__

#define __TREE_HPP__

enum RBTreeNodeColor { RED, BLACK };

struct RBTreeNode {
  char *data;
  RBTreeNode *left;
  RBTreeNode *right;
  RBTreeNode *parent;
  RBTreeNodeColor color;
};

struct RBTree {
  RBTreeNode TNULL;
  RBTree() { TNULL = {nullptr, nullptr, nullptr, nullptr, BLACK}; }
};

#endif
