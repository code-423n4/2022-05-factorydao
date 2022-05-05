from random import randbytes, randint
from brownie import web3
import hexbytes
from eth_abi import encode_abi

# node = {
#   index,
#   hash,
#   parentIndex,
#   leftChildIndex,
#   rightChildIndex
# }

zeroHash = hexbytes.HexBytes('0x0000000000000000000000000000000000000000000000000000000000000000')


def randomData(type):
    if type == 'address':
        return web3.toChecksumAddress('0x' + randbytes(20).hex())
    elif type == 'uint256':
        return randint(1, 2 ** 22)
    elif type == 'string':
        return randbytes(20).hex()


def generateRandomData(preload, keys, types, numLeaves):
    leaves = preload

    for i in range(numLeaves):
        if i % 10000 == 0:
            print(i)
        leaves.append({
            keys[i]: randomData(types[i])
            for i in range(len(keys))
        })

    return leaves


def createMerkleProof(tree, leaf):
    x = {**leaf}
    # debugger
    proof = []
    # print('x', x)
    while x['parentIndex'] > -1:
        parent = tree['nodes'][x['parentIndex']]
        flip = x['index'] == parent['leftChildIndex']
        if flip:
            proof.append(tree['nodes'][parent['rightChildIndex']]['hash'])
        else:
            proof.append(tree['nodes'][parent['leftChildIndex']]['hash'])
        x = parent
    return proof


def getLeafHash(obj, hashTypes, hashKeys):
    values = [obj[x] for x in hashKeys]
    return web3.keccak(encode_abi(hashTypes, values))


def checkMerkleProof(proof, tree, leaf):
    a = getLeafHash(leaf['data'], tree['hash_types'], tree['hash_keys'])
    # print('leaf hash merkle.py', a.hex())
    for i in range(len(proof)):
        b = proof[i]
        # console.log('proof step', { a, b })
        p = parentHash(a, b)
        a = p[0]
        # print(p[0].hex())

    correct = a == tree['root']['hash']
    # console.log({ correct, a, root })
    return correct


def createMerkleTree(leaves, hashTypes, hashKeys):
    numNodes = 0
    allNodes = []
    for x in leaves:
        hash = getLeafHash(x, hashTypes, hashKeys)

        allNodes.append({
            'index': numNodes,
            'data': x,
            'hash': hash,
            'parentIndex': -1,
            'leftChildIndex': -1,
            'rightChildIndex': -1
        })
        numNodes += 1

    currentRow = [x['index'] for x in allNodes]
    parentRow = []
    allRows = []
    while len(currentRow) > 1:
        # handle case where the tree is not binary by adding zero hash
        if len(currentRow) % 2:
            allNodes.append({
                'index': numNodes,
                'hash': zeroHash,
                'data': None,
                'parentIndex': -1,
                'leftChildIndex': -1,
                'rightChildIndex': -1
            })
            numNodes += 1
            currentRow.append(numNodes - 1)

        # loop over current row
        for i in range(0, len(currentRow), 2):
            [pHash, flip] = parentHash(
                allNodes[currentRow[i]]['hash'],
                allNodes[currentRow[i + 1]]['hash']
            )
            newNode = {
                'index': numNodes,
                'hash': pHash,
                'data': None,
                'parentIndex': -1,
                'leftChildIndex': allNodes[currentRow[i + 1]]['index'] if flip else allNodes[currentRow[i]]['index'],
                'rightChildIndex': allNodes[currentRow[i]]['index'] if flip else allNodes[currentRow[i + 1]]['index']
            }
            numNodes += 1
            allNodes[currentRow[i]]['parentIndex'] = numNodes - 1
            allNodes[currentRow[i + 1]]['parentIndex'] = numNodes - 1
            allNodes.append(newNode)
            parentRow.append(newNode['index'])

        # keep track of rows
        allRows.append(currentRow)
        # move pointer to next row
        currentRow = parentRow
        # zero out parent
        parentRow = []

    allRows.append(currentRow)
    return {
        'rows': allRows,
        'nodes': allNodes,
        'root': allNodes[-1],
        'hash_keys': hashKeys,
        'hash_types': hashTypes
    }


def parentHash(a, b):
    c = None
    if a < b:
        c = [web3.keccak(hexstr=a.hex() + b.hex()[2:]), False]
    else:
        c = [web3.keccak(hexstr=b.hex() + a.hex()[2:]), True]
    # print('merkle.py parentHash', a.hex(), b.hex(), c[0].hex())
    return c
#
# def generateRandomResistorData(numLeaves):
#     leaves = [
#         {
#             "destination": "0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1",
#             "endTime": 1627885337,
#             "minTotalPayments": web3.utils.toWei('1000'),
#             "maxTotalPayments": web3.utils.toWei('2000')
#         }
#     ]
#
#     for i in range(numLeaves):
#         if i % 10000 == 0:
#             print('i', i)
#         rand = web3.utils.randomHex(3).toString()
#         rand2 = web3.utils.randomHex(4).toString()
#         leaves.append({
#             "destination": web3.utils.randomHex(20),
#             "endTime": web3.utils.randomHex(6),
#             "minTotalPayments": rand,
#             "maxTotalPayments": rand2
#         })
#
#     return {'leaves': leaves}


def generateRandomTree(preload, hash_keys, hash_types, numLeaves):
    leaves = generateRandomData(preload, hash_keys, hash_types, numLeaves)
    tree = createMerkleTree(leaves, hash_types, hash_keys)
    return tree


def test():
  address_preload = [{"address": web3.toChecksumAddress("0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1")}]
  address_hash_keys = ['address']
  address_hash_types = ['address']

  address_leaves = generateRandomData(address_preload, address_hash_keys, address_hash_types, 100)
  print(address_leaves)

  metadata_hash_keys = ['tokenId', 'uri']
  metadata_hash_types = ['uint256', 'string']
  metadata_leaves = generateRandomData([], metadata_hash_keys, metadata_hash_types, 10)
  print(metadata_leaves)

  address_tree = createMerkleTree(address_leaves, address_hash_types, address_hash_keys)
  target_address = address_tree['nodes'][0]
  metadata_tree = createMerkleTree(metadata_leaves, metadata_hash_types, metadata_hash_keys)
  target_metadata = metadata_tree['nodes'][0]
  address_proof = createMerkleProof(address_tree, target_address)
  metadata_proof = createMerkleProof(metadata_tree, target_metadata)
  address_correct = checkMerkleProof(address_proof, address_tree, target_address)
  metadata_correct = checkMerkleProof(metadata_proof, metadata_tree, target_metadata)

  print('addressMerkleRoot', address_tree['root'])
  print('metadataMerkleRoot', metadata_tree['root'])
  print('addressProof', address_proof)
  print('metadataProof', metadata_proof)

  print(address_correct)
  print(metadata_correct)

# test()