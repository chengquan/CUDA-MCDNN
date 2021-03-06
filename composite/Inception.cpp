#include"Inception.h"


/*
 * Inception constructor
 * */
Inception::Inception(LayersBase* prevLayer,
                     int sign, 
                     float* rate, 
                     const param_tuple& args)
{
    std::tie(one, three, five, three_reduce, five_reduce, pool_proj,
             inputAmount, inputImageDim, epsilon, lambda) = args;

    dstData = NULL;
    diffData = NULL;
    lrate = rate;
    InnerLayers = new Layers[4];

    Conv_one = new ConvLayer("one", sign,
                             ConvLayer::param_tuple(0, 0, 1, 1, 1,
                                                    one,
                                                    inputAmount, 
                                                    inputImageDim, 
                                                    epsilon, 
                                                    *lrate, 
                                                    lambda));

    Conv_three_reduce = new ConvLayer("three_reduce", sign,
                                      ConvLayer::param_tuple(0, 0, 1, 1, 1,
                                                             three_reduce,
                                                             inputAmount, 
                                                             inputImageDim, 
                                                             epsilon, 
                                                             *lrate, 
                                                             lambda));

    Conv_three = new ConvLayer("three", sign,
                               ConvLayer::param_tuple(1, 1, 1, 1, 3,
                                                      three,
                                                      three_reduce, 
                                                      inputImageDim, 
                                                      epsilon, 
                                                      *lrate, 
                                                      lambda));

    Conv_five_reduce = new ConvLayer("five_reduce", sign,
                                     ConvLayer::param_tuple(0, 0, 1, 1, 1,
                                                            five_reduce,
                                                            inputAmount, 
                                                            inputImageDim, 
                                                            epsilon, 
                                                            *lrate, 
                                                            lambda));

    Conv_five = new ConvLayer("five", sign,
                              ConvLayer::param_tuple(2, 2, 1, 1, 5,
                                                     five,
                                                     five_reduce, 
                                                     inputImageDim,
                                                     epsilon, 
                                                     *lrate, 
                                                     lambda));

    max_pool = new PoolLayer("max_pool",
                             PoolLayer::param_tuple("POOL_MAX", 3, 1, 1, 1, 1,
                                                    inputImageDim, 
                                                    inputAmount));

    Conv_pool_proj = new ConvLayer("pool_proj",sign,
                                   ConvLayer::param_tuple(0, 0, 1, 1, 1,
                                                          pool_proj,
                                                          inputAmount, 
                                                          inputImageDim, 
                                                          epsilon, 
                                                          *lrate, 
                                                          lambda));
    /*mainly use in backpropagation*/
    share_Layer = new ShareLayer("share");

   /*four branch*/
   InnerLayers[0].storLayers("one", Conv_one);
   InnerLayers[1].storLayers("three_reduce", Conv_three_reduce);
   InnerLayers[1].storLayers("three", Conv_three);
   InnerLayers[2].storLayers("five_reduce", Conv_five_reduce);
   InnerLayers[2].storLayers("five", Conv_five);
   InnerLayers[3].storLayers("max_pool", max_pool);
   InnerLayers[3].storLayers("pool_proj", Conv_pool_proj);

    /*the last layer is shared layer*/
    for(int i = 0; i < 4; i++)
    {
        InnerLayers[i].getLayer(InnerLayers[i].getLayersName(0))->insertPrevLayer( prevLayer);
        InnerLayers[i].getLayer(InnerLayers[i].getLayersName(InnerLayers[i].getLayersNum() - 1))->insertNextlayer(share_Layer);
    }

    concat = new Concat(InnerLayers, Concat::param_tuple(one, three, five, pool_proj));
}

/*get result*/
float* Inception::getConcatData()
{
    return dstData;
}

/*get delta*/
float* Inception::getInceptionDiffData()
{
    return diffData;
}

Inception::~Inception()
{
    delete share_Layer;
    delete concat;
    delete InnerLayers;
    delete Conv_one;
    delete Conv_three_reduce;
    delete Conv_three;
    delete Conv_five;
    delete Conv_five_reduce;
    delete Conv_pool_proj;
    delete max_pool;
}

/*
 * Inception forwardPropagation
 * */
void Inception::forwardPropagation(string train_or_test)
{
    LayersBase* layer;

    for(int i = 0; i < 4; i++)
    {
        for(int j = 0; j < InnerLayers[i].getLayersNum(); j++)
        {
            layer = InnerLayers[i].getLayer(InnerLayers[i].getLayersName(j));
            layer->lrate = *lrate;
            layer->forwardPropagation(train_or_test);
        }
    }
    /*get the inception result data*/
    dstData = concat->forwardSetup();
}


/*
 * Inception backwardPropagation
 * */
void Inception::backwardPropagation(float*& nextLayerDiffData, float Momentum)
{
    LayersBase* layer;
    for(int i = 0; i < 4; i++)
    {
        concat->split_DiffData(i, nextLayerDiffData);

        for(int j = InnerLayers[i].getLayersNum() - 1; j >= 0; j--)
        {
            layer = InnerLayers[i].getLayer(InnerLayers[i].getLayersName(j));
            layer->backwardPropagation(Momentum);
        }
    }
    /*get inception diff*/
    diffData = concat->backwardSetup();
}
