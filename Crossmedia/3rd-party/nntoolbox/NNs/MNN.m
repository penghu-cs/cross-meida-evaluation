classdef MNN < INN
    %MNN "siamese" network where each tuple xi is pulled at a given
    %distance ti
    %Each tuple has its own margin
    %
    %   min 0.5 * max(0, t - (\eta(xi) - \eta(xj)).^2).^2
    %
    properties
        net
        netCloned
        
        batchSize
        nwts
    end
    
    methods(Static)
        function checkInput(x)
            if ~isstruct(x)
                error('input data is not struct');
            end
            
            if ~isfield(x, 'x1')
                error('field x1 missing');
            end
            
            if ~isfield(x, 'x2')
                error('field x2 missing');
            end
        end
    end
    
    methods
        function obj = MNN(net)
            obj.nwts = net.nParams();
            
            obj.net = net;
            obj.netCloned = net.clone();
            
            obj.batchSize = realmax;
        end
        
        function o = clone(obj)
            o = SNN(obj.net.clone());
            o.batchSize = obj.batchSize;
        end
        
        function y = fwd(obj, x)
            y = obj.net.fwd(x);
        end
        
        function w = getParams(obj)
            w = obj.net.getParams();
        end
        
        function setParams(obj, w)
            obj.net.setParams(w);
            obj.netCloned.setParams(w);
        end
        
        function n = nParams(obj)
            n = obj.nwts;
        end
        
        function g = computeGradOnly(obj)
            warning('not implemented for SNN')
        end
        
        function g = computeGradOnlyCell(obj)
            warning('not implemented for SNN')
        end
        
        function [cost, g] = grad(obj, w, x, t)
            SNN.checkInput(x);
            
            % set params
            obj.setParams(w);
            
            % loop over batches to compute the gradient
            ndata = obj.net.getNData(t); %size(x.x1, 1);
            nBatches = ceil(ndata/obj.batchSize);
            
            to = min(obj.batchSize, ndata);
            x_.x1 = obj.net.getX(x.x1, 1:to);
            x_.x2 = obj.net.getX(x.x2, 1:to);
            t_ = obj.net.getT(t, 1:to);
            [cost, g] = obj.grad_(x_, t_);
            for i=2:nBatches
                from = (i - 1) * obj.batchSize + 1;
                to = min(i * obj.batchSize, ndata);
                
                x_.x1 = obj.net.getX(x.x1, from:to);
                x_.x2 = obj.net.getX(x.x2, from:to);
                t_ = obj.net.getT(t, from:to);
                
                [cost_, g_] = obj.grad_(x_, t_);
                cost = cost + cost_;
                g = g + g_;
            end
        end
        
        function [cost, g] = gradCell(obj, w, x, t)
            SNN.checkInput(x);
            
            % set params
            obj.setParams(w);
            
            % loop over batches to compute the gradient
            ndata = obj.net.getNData(t); %size(x.x1, 1);
            nBatches = ceil(ndata/obj.batchSize);
            
            to = min(obj.batchSize, ndata);
            x_.x1 = obj.net.getX(x.x1, 1:to);
            x_.x2 = obj.net.getX(x.x2, 1:to);
            t_ = obj.net.getT(t, 1:to);
            [cost, g] = obj.gradCell_(x_, t_);
            for i=2:nBatches
                from = (i - 1) * obj.batchSize + 1;
                to = min(i * obj.batchSize, ndata);
                
                x_.x1 = obj.net.getX(x.x1, from:to);
                x_.x2 = obj.net.getX(x.x2, from:to);
                t_ = obj.net.getT(t, from:to);
                
                [cost_, g_] = obj.gradCell_(x_, t_);
                cost = cost + cost_;
                for j = 1:length(g)
                    g{j} = cellfun(@plus, g{j}, g_{j}, 'UniformOutput', false);
                end
            end
        end
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    methods(Access=protected)
        function [cost, g] = grad_(obj,x,t)
            %% fwd
            y1 = obj.net.fwd(x.x1);
            y2 = obj.netCloned.fwd(x.x2);
            
            %% err
            delout = y1 - y2;
            delout_sq = delout.^2;
            
            l2_sq = sum(delout_sq, 2);
            m = max(0, t - l2_sq);
            
            c_rep = repmat(m, [1, size(delout,2)]);
            delout = c_rep .* (-2 * delout);
            
            %% cost
            outerr = sum(m.^2, 2);
            cost = 0.5 * sum(outerr);

            %% grad
            obj.net.d{length(obj.net.h)} = delout;
            obj.netCloned.d{length(obj.net.h)} = -delout;
            % deriv out
            obj.net.d{length(obj.net.h)} = obj.net.acts{end}.deriv1(obj.net.h{end}, obj.net.d{length(obj.net.h)});
            obj.netCloned.d{length(obj.netCloned.h)} = obj.netCloned.acts{end}.deriv1(obj.netCloned.h{end}, obj.netCloned.d{length(obj.netCloned.h)});
            
            obj.net.bkp();
            obj.netCloned.bkp();
            
            g = obj.net.computeGradOnly() + obj.netCloned.computeGradOnly();
        end
        
        function [cost, g] = gradCell_(obj,x,t)
            %% fwd
            y1 = obj.net.fwd(x.x1);
            y2 = obj.netCloned.fwd(x.x2);
            
            
            %% err
            delout = y1 - y2;
            delout_sq = delout.^2;
            
            % Dissimilar
            l2_sq = sum(delout_sq, 2);
            m = max(0, t - l2_sq);
            
            c_rep = repmat(m, [1, size(delout,2)]);
            delout = c_rep .* (-2 * delout);
            
            %% cost
            outerr = sum(m.^2, 2);
            cost = 0.5 * sum(outerr);
            
            
            %% grad
            obj.net.d{length(obj.net.h)} = delout;
            obj.netCloned.d{length(obj.net.h)} = -delout;
            % deriv out
            obj.net.d{length(obj.net.h)} = obj.net.acts{end}.deriv1(obj.net.h{end}, obj.net.d{length(obj.net.h)});
            obj.netCloned.d{length(obj.netCloned.h)} = obj.netCloned.acts{end}.deriv1(obj.netCloned.h{end}, obj.netCloned.d{length(obj.netCloned.h)});
            
            obj.net.bkp();
            obj.netCloned.bkp();
            
            g1 = obj.net.computeGradOnlyCell();
            g2 = obj.netCloned.computeGradOnlyCell();
            for i = 1:length(g1)
                g{i} = cellfun(@plus, g1{i}, g2{i}, 'UniformOutput', false);
            end
        end
    end
end
