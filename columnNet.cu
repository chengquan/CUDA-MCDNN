#include"columnNet.cuh"
#include"config/config.h"
#include"./readData/readNetWork.h"
#include"./layers/dataLayer.h"
#include"./layers/convLayer.h"
#include"./layers/poolLayer.h"
#include"./layers/InceptionLayer.h"
#include"./layers/hiddenLayer.h"
#include"./layers/dropOutLayer.h"
#include"./layers/activationLayer.h"
#include"./layers/LRNLayer.h"
#include"./layers/softMaxLayer.h"
#include "./layers/voteLayer.h"
#include"./common/cuMatrixVector.h"
#include"./common/cuMatrix.h"
#include"./common/utility.cuh"
#include<iostream>
#include<time.h>
#include <queue>
#include <set>
#include"math.h"
const bool DFS_TRAINING = true;
const bool DFS_TEST = true;

using namespace std;

/*create netWork*/
void creatColumnNet(int sign)
{
    layersBase* baseLayer;
    int layerNum = config::instanceObjtce()->getLayersNum();
    configBase* layer = config::instanceObjtce()->getFirstLayers();
    queue<configBase*>que;
    que.push(layer);
    set<configBase*>hash;
    hash.insert( layer );
    while(!que.empty()){
        layer = que.front();
        que.pop();
        if((layer->_type) == "DATA")
        {
            baseLayer = new dataLayer(layer->_name);
        }else if((layer->_type) == "CONV")
        {
            baseLayer = new convLayer (layer->_name, sign);
        }else if((layer->_type == "POOLING"))
        {
            baseLayer = new poolLayer (layer->_name);
        }else if((layer->_type) == "HIDDEN")
        {
            baseLayer = new hiddenLayer(layer->_name, sign);
        }else if((layer->_type) == "SOFTMAX")
        {
            baseLayer = new softMaxLayer(layer->_name);
        }else if((layer->_type) == "ACTIVATION")
        {
            baseLayer = new activationLayer(layer->_name);
        }else if((layer->_type) == "LRN")
        {
            baseLayer = new LRNLayer(layer->_name);
        }else if((layer->_type) == "INCEPTION")
        {
            baseLayer = new InceptionLayer(layer->_name, sign);
        }else if((layer->_type) == "DROPOUT")
        {
            baseLayer = new dropOutLayer(layer->_name);
        }

        Layers::instanceObject()->storLayers(layer->_input, layer->_name, baseLayer);
        for(int i = 0; i < layer->_next.size(); i++){
            if( hash.find( layer->_next[i] ) == hash.end()){
                hash.insert( layer->_next[i] );
                que.push( layer->_next[i]);
            }
        }
    }

    if(sign == READ_FROM_FILE) readNetWork();
}

/*predict the result*/
void resultPredict(string train_or_test)
{
    int size = Layers::instanceObject()->getLayersNum();
    configBase* config = (configBase*) config::instanceObjtce()->getFirstLayers();
    queue<configBase*>que;
    que.push(config);
    set<configBase*>hash;
    hash.insert(config);
    while(!que.empty()){
        config = que.front();
        que.pop();
        layersBase* layer = (layersBase*)Layers::instanceObject()->getLayer(config->_name);
        layer->forwardPropagation(train_or_test);
        for(int i = 0; i < config->_next.size(); i++){
            if( hash.find( config->_next[i] ) == hash.end()){
                hash.insert( config->_next[i] );
                que.push( config->_next[i] );
            }
        }
    }
}

/*test netWork*/
void predictTestData(cuMatrixVector<float>&testData, cuMatrix<int>* &testLabel, int batchSize)
{
    dataLayer* datalayer = static_cast<dataLayer*>( Layers::instanceObject()->getLayer("data"));

    for(int i=0;i<(testData.size()+batchSize)/batchSize;i++)
    {
        datalayer->getBatch_Images_Label(i , testData, testLabel);
        resultPredict("test");
    }
}

/*train netWork*/
void getNetWorkCost(float&Momentum)
{
    resultPredict("train");

    configBase* config = (configBase*) config::instanceObjtce()->getLastLayer();
    queue<configBase*>que;
    que.push(config);
    set<configBase*>hash;
    hash.insert(config);
    while(!que.empty()){
        config = que.front();
        que.pop();
        layersBase* layer = (layersBase*)Layers::instanceObject()->getLayer(config->_name);
        layer->backwardPropagation(Momentum);
     
        for(int i = 0; i < config->_prev.size(); i++){
            if( hash.find( config->_prev[i] ) == hash.end()){
                hash.insert(config->_prev[i]);
                que.push(config->_prev[i]);
            }
        }
    }
}

std::vector<configBase*> g_vQue;

/* voting */
void dfsResultPredict( configBase* config, cuMatrixVector<float>& testData, cuMatrix<int>*& testLabel, int nBatchSize)
{
    g_vQue.push_back( config );
    if( config->_next.size() == 0 ){
        //printf("%s\n", config->_name.c_str());

        dataLayer* datalayer = static_cast<dataLayer*>( Layers::instanceObject()->getLayer("data"));

        for(int i = 0; i < (testData.size() + nBatchSize - 1) / nBatchSize; i++)
        {
            datalayer->getBatch_Images_Label(i , testData, testLabel);
            for(int j = 0; j < g_vQue.size(); j++)
            {
                layersBase* layer = (layersBase*)Layers::instanceObject()->getLayer(g_vQue[j]->_name);
                layer->forwardPropagation("test");

                // is softmax, then vote
                if( j == g_vQue.size() - 1 ){
                    VoteLayer::instance()->vote( i , nBatchSize, layer->dstData );
                }
            }
        }
    }

    for(int i = 0; i < config->_next.size(); i++){
        configBase* tmpConfig = config->_next[i];
        layersBase* layer = (layersBase*)Layers::instanceObject()->getLayer( config->_name );
        layer->setCurBranchIndex(i);
        dfsResultPredict( tmpConfig, testData, testLabel, nBatchSize );
    }
    g_vQue.pop_back();
}

void dfsTraining(configBase* config, float nMomentum, cuMatrixVector<float>& trainData, cuMatrix<int>* &trainLabel, int& iter)
{
    g_vQue.push_back(config);

    /*如果是一个叶子节点*/
    if (config->_next.size() == 0){
        dataLayer* datalayer = static_cast<dataLayer*>(Layers::instanceObject()->getLayer("data"));
        datalayer->RandomBatch_Images_Label(trainData, trainLabel);

        for(int i = 0; i < g_vQue.size(); i++){
            //printf("f %d %s\n", i, g_vQue[i]->_name.c_str());
            layersBase* layer = (layersBase*)Layers::instanceObject()->getLayer(g_vQue[i]->_name);
            layer->forwardPropagation( "train" );
        }
        for( int i = g_vQue.size() - 1; i>= 0; i--){
        //printf("b %d %s\n", i, g_vQue[i]->_name.c_str());
            layersBase* layer = (layersBase*)Layers::instanceObject()->getLayer(g_vQue[i]->_name);
            /*反向传到减枝*/
            /*if( i - 1 >= 0)
            {
                configBase* b1 = g_vQue[i - 1]->_next[0];
                configBase* b2 = g_vQue[i];
                if( b1 != b2 )break;
            }
            */
            layer->backwardPropagation( nMomentum );
        }
    }
    /*如果不是叶子节点*/
    for(int i = 0; i < config->_next.size(); i++){
        configBase* tmpConfig = config->_next[i];
        layersBase* layer = (layersBase*)Layers::instanceObject()->getLayer( config->_name );
        layer->setCurBranchIndex(i);
        dfsTraining( tmpConfig, nMomentum, trainData, trainLabel, iter);
    }
    g_vQue.pop_back();
}

/*training netWork*/
void cuTrainNetWork(cuMatrixVector<float> &trainData, 
        cuMatrix<int>* &trainLabel, 
        cuMatrixVector<float> &testData,
        cuMatrix<int>*&testLabel,
        int batchSize
        )
{
    cout<<"TestData Forecast The Result..."<<endl;
    predictTestData(testData, testLabel, batchSize);
    cout<<endl;

    cout<<"NetWork training......"<<endl;
    int epochs = config::instanceObjtce()->get_trainEpochs();
    int iter_per_epo = config::instanceObjtce()->get_iterPerEpo();
    int layerNum = Layers::instanceObject()->getLayersNum();
    double nMomentum[]={0.90,0.91,0.92,0.93,0.94,0.95,0.96,0.97,0.98,0.99};
    int epoCount[]={80,80,80,80,80,80,80,80,80,80};
    float Momentum = 0.9;
    int id = 0;

    clock_t start, stop;
    double runtime;

    start = clock();
    for(int epo = 0; epo < epochs; epo++)
    {
        dataLayer* datalayer = static_cast<dataLayer*>(Layers::instanceObject()->getLayer("data"));

        Momentum = nMomentum[id];

        clock_t inStart, inEnd;
        inStart = clock();
        configBase* config = (configBase*) config::instanceObjtce()->getFirstLayers();
        if( DFS_TRAINING == false ){
            /*train network*/
            for(int iter = 0 ; iter < iter_per_epo; iter++)
            {
                datalayer->RandomBatch_Images_Label(trainData, trainLabel);
                getNetWorkCost(Momentum);
            }
        }
        else{
            //printf("error\n");
            int iter = 0;
            g_vQue.clear();
            while(iter < iter_per_epo){
                dfsTraining(config, Momentum, trainData, trainLabel, iter);
                iter++ ;
            }
        }

        inEnd = clock();

        config = (configBase*) config::instanceObjtce()->getFirstLayers();
        //adjust learning rate
        queue<configBase*> que;
        set<configBase*> hash;
        hash.insert(config);
        que.push(config);
        while( !que.empty() ){
            config = que.front();
            que.pop();
            layersBase * layer = (layersBase*)Layers::instanceObject()->getLayer(config->_name);
            layer->adjust_learnRate(epo, FLAGS_lr_gamma, FLAGS_lr_power);

            for(int i = 0; i < config->_next.size(); i++){
                if( hash.find(config->_next[i]) == hash.end()){
                    hash.insert(config->_next[i]);
                    que.push(config->_next[i]);
                }
            }
        }

        if(epo && epo % epoCount[id] == 0)
        {
            id++;
            if(id>9) id=9;
        }

        /*test network*/
        cout<<"epochs: "<<epo<<" ,Time: "<<(inEnd - inStart)/CLOCKS_PER_SEC<<"s,";
        if( DFS_TEST == false){
            predictTestData( testData, testLabel, batchSize );
        }
        else{
            VoteLayer::instance()->clear();
            static float fMax = 0;
            configBase* config = (configBase*) config::instanceObjtce()->getFirstLayers();
            dfsResultPredict(config, testData, testLabel, batchSize);
            float fTest = VoteLayer::instance()->result();
            if ( fMax < fTest ) fMax = fTest;
            printf(" test_result %f/%f ", fTest, fMax);
        }
        cout<<" ,Momentum: "<<Momentum<<endl;

    }

    stop = clock();
    runtime = stop - start;
    cout<< epochs <<" epochs total rumtime is: "<<runtime /CLOCKS_PER_SEC<<" Seconds"<<endl;
}
