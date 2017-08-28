import tensorflow as tf
import sys
from time import time

# Given a pair of x and y (each being a list or a np array) and a
# batch size, return a generator function which will yield the input
# in bs-sized chunks. Attention: if the size of the input is not
# divisible by bs, then the remainer will not be fed. Consider
# shuffling the input.
def bilist_generator(l,bs):
    (l0,l1) = l
    def gen():
      for i in range(0, bs*(len(l0)//bs), bs):
        yield (l0[i:i+bs],l1[i:i+bs])
    return gen

# optimizer is one of tf.train.GradientDescentOptimizer(0.05), tf.train.AdamOptimizer() etc.
def train (session, model, train_generator, valid_generator=bilist_generator(([],[]),1), optimizer=tf.train.AdamOptimizer(), epochs=100, callbacks=[]):
    (training_phase,x,y,y_,accuracy,loss,params,gradients) = model
    # must come before the initializer (this line creates variables!)
    train = optimizer.apply_gradients(zip(model["gradients"], model["params"]))
    # train = optimizer.minimize(loss)
    session.run(tf.local_variables_initializer())
    session.run(tf.global_variables_initializer())
    def halfEpoch(isTraining):
        totalAccur = 0
        totalLoss = 0
        n = 0
        print ("Training" if isTraining else "Validation", end="")
        start_time = time()
        for (x_train,y_train) in train_generator() if isTraining else valid_generator():
            print(".",end="")
            sys.stdout.flush()
            _,lossAcc,accur = session.run([model["train"],model["loss"],model["accuracy"]], feed_dict={model["x"]:x_train, model["y"]:y_train, model["training_phase"]:isTraining})
            n+=1
            totalLoss += lossAcc
            totalAccur += accur
        end_time = time()
        if n > 0:
            avgLoss = totalLoss / float(n)
            avgAccur = totalAccur / float(n)
            print(".")
            print ("Time=%.1f" % (end_time - start_time), "loss=%g" % avgLoss, "accuracy=%.3f" % avgAccur)
            return {"loss":avgLoss,"accuracy":avgAccur,"time":(end_time - start_time)}
        else:
            print ("No data")
            return {"loss":0,"accur":0,"time":0}

    for e in range(epochs):
        print ("Epoch {0}/{1}".format(e, epochs))
        tr = halfEpoch(True)
        va = halfEpoch(False)
        if any(c({"train":tr, "val":va}) for c in callbacks):
            break

def StopWhenValidationGetsWorse(patience = 1):
    bestLoss = 10000000000
    p = patience
    def callback(values):
        nonlocal bestLoss, p, patience
        newLoss = values["val"]["loss"]
        if newLoss > bestLoss:
            p -= 1
        else:
            bestLoss = newLoss
            p = patience
        if p <= 0:
            return True
        return False
    return callback

def StopWhenGoodAccuracy(accur = .99):
    def callback(values):
        nonlocal accur
        return values["val"]["accuracy"] > accur
    return callback


def predict (session, model, xs):
    bs = model["batch_size"]
    zeros = np.zeros_like(xs[0])
    for i in range(0, bs*(len(xs)//bs), bs):
        chunk = xs[i:i+bs]
        yield (chunk + [zeros] * bs-len(chunk))


    return np.concatenate([session.run(model["y"], feed_dict={model["x"]:x_train, model["training_phase"]:False}) (x_train,i) in gen])

    # k-Beam search at index i in a sequence.
    # work with k-size batch.
    # keep for every j < k a sum of the log probs, r(j).
    # for every possible output work w at the i-th step in the sequence, compute r'(j,w) = r(j) * logit(i,w)
    # compute the k pairs (j,w) which minimize r'(j,w). Let M this set.
    # r(l) = r'(j,w) for (l,(j,w)),in enumarate(M)
    
    
    # # beam search
    # def translate(src_sent, k=1):
    #     # (log(1), initialize_of_zeros)
    #     k_beam = [(0, [0]*(sequence_max_len+1))]
    
    #     # l : point on target sentence to predict
    #     for l in range(sequence_max_len):
    #         all_k_beams = []
    #         for prob, trg_sent_predict in k_beam:
    #             predicted       = encoder_decoder.predict([np.array([src_sent]), np.array([trg_sent_predict])])[0]
    #             # top k!
    #             possible_k_trgs = predicted[l].argsort()[-k:][::-1]
    
    #             # add to all possible candidates for k-beams
    #             all_k_beams += [
    #                 (
    #                     sum(np.log(predicted[i][trg_sent_predict[i+1]]) for i in range(l)) + np.log(predicted[l][next_wid]),
    #                     list(trg_sent_predict[:l+1])+[next_wid]+[0]*(sequence_max_len-l-1)
    #                 )
    #                 for next_wid in possible_k_trgs
    #             ]
    #         # top k
    #         k_beam = sorted(all_k_beams)[-k:]
